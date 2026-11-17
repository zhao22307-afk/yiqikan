/// 夸克网盘（14 §2）：分享 token → 目录 → 直链；外加扫码登录三步。
///
/// 这一轮只把结构和真实请求搭好，验证逻辑等真 Cookie 到手再确认。
/// 规矩：cookie 只进 SecureStore（key `cred_quark_cookie`），日志里只出现脱敏地址。
library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/resolver.dart';
import '../local/secure_store.dart';
import 'netdisk_adapter.dart';
import 'netdisk_http.dart';

/// 扫码状态：0 待扫 / 1 已扫待确认 / 2 已确认 / 3 过期（其它值一律当 waiting）
enum QuarkQrState {
  waiting,
  scanned,
  confirmed,
  expired;

  static QuarkQrState fromCode(int code) {
    switch (code) {
      case 1:
        return QuarkQrState.scanned;
      case 2:
        return QuarkQrState.confirmed;
      case 3:
        return QuarkQrState.expired;
      default:
        return QuarkQrState.waiting;
    }
  }

  String get text {
    switch (this) {
      case QuarkQrState.waiting:
        return '等扫码…';
      case QuarkQrState.scanned:
        return '已扫码，等手机确认';
      case QuarkQrState.confirmed:
        return '扫码成功，正在换 Cookie';
      case QuarkQrState.expired:
        return '二维码已过期，已刷新';
    }
  }
}

/// 扫码登录的三步返回值（第 2 步的二维码内容直接给 UI 渲染）
class QuarkQrSession {
  const QuarkQrSession({required this.token, required this.qrContent, required this.requestId});

  final String token;

  /// 让用户扫的内容（夸克 App 里那串 https://su.quark.cn/...）
  final String qrContent;
  final String requestId;
}

class QuarkAdapter extends NetdiskAdapter {
  QuarkAdapter({
    required super.account,
    required this.cookie,
    required this.store,
    Dio? dio,
    Dio? loginDio,
  })  : _dio = dio ??
            newNetdiskDio(baseHeaders: <String, String>{
              'Cookie': cookie,
              'Referer': 'https://pan.quark.cn/',
              'User-Agent': kDesktopUa,
            }),
        _loginDio = loginDio ?? newNetdiskDio();

  static const String apiBase = 'https://drive-pc.quark.cn';
  static const String loginBase = 'https://uop.quark.cn';
  static const String accountBase = 'https://pan.quark.cn';

  static const String credKey = 'cred_quark_cookie';

  /// Cookie 里至少要有一个主登录态字段（14 §2.0）
  static const List<String> cookieKeys = <String>['__puus', '__pus', 'b-user-id', '__uid'];

  static bool looksLikeCookie(String raw) =>
      cookieKeys.any((String k) => raw.contains('$k='));

  final String cookie;
  final SecureStore store;
  final Dio _dio;
  final Dio _loginDio;

  @override
  NetdiskKind get kind => NetdiskKind.quark;

  Map<String, String> get _query => <String, String>{'pr': 'ucpro', 'fr': 'pc'};

  String get _pwdId => account.extra['pwd_id'] ?? '';
  String get _stoken => account.extra['stoken'] ?? '';

  @override
  Future<bool> verify() async {
    if (!looksLikeCookie(cookie)) {
      throw const AuthExpiredException(hint: '把 pan.quark.cn 的完整 Cookie 粘进来');
    }
    final Response<dynamic> r = await _dio.get<dynamic>(
      '$apiBase/1/clouddrive/config',
      queryParameters: _query,
    );
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code == 31001) throw const AuthExpiredException();
    if (code != 0 && code != 200) {
      throwBizCode(code, authCodes: <int>{31001, 401}, what: '夸克');
    }
    return true;
  }

  // ---------- 扫 码 登 录 ----------

  /// 第 1 步：拿 token + 二维码内容
  Future<QuarkQrSession> qrToken() async {
    final Response<dynamic> r = await _loginDio.get<dynamic>(
      '$loginBase/cas/ajax/getTokenForQrcodeLogin',
    );
    final Map<String, Object?> body = _asMap(r.data);
    final Map<String, Object?> members = _asMap(_asMap(body['data'])['members']);
    final String token = '${members['token'] ?? ''}';
    if (token.isEmpty) throw const ParseException('夸克扫码：没拿到 token');
    return QuarkQrSession(
      token: token,
      qrContent: 'https://su.quark.cn/4_eMHBJ?uc_param_str=&token=$token',
      requestId: _uuid(),
    );
  }

  /// 第 3 步：轮询。把 0/1/2/3 翻成四种状态（过期要能自动重开，否则用户以为网卡了）
  Future<({QuarkQrState state, String ticket})> qrPoll(QuarkQrSession s) async {
    final Response<dynamic> r = await _loginDio.get<dynamic>(
      '$loginBase/cas/ajax/getServiceTicketByQrcodeToken',
      queryParameters: <String, String>{
        'token': s.token,
        'client_id': '532',
        'v': '1.1',
        'request_id': s.requestId,
      },
    );
    final Map<String, Object?> members = _asMap(_asMap(_asMap(r.data)['data'])['members']);
    return (
      state: QuarkQrState.fromCode(_int(members['status'])),
      ticket: '${members['service_ticket'] ?? ''}',
    );
  }

  /// 第 4 步：用 ticket 换 Cookie（把 set-cookie 全拼起来）
  Future<String> cookieFromTicket(String ticket) async {
    final Response<dynamic> r = await _loginDio.get<dynamic>(
      '$accountBase/account/info',
      queryParameters: <String, String>{'st': ticket, 'lw': 'scan'},
      options: Options(followRedirects: false),
    );
    final List<String>? raw = r.headers['set-cookie'];
    if (raw == null || raw.isEmpty) {
      throw const AuthExpiredException(hint: '扫码确认后没换到 Cookie，重新扫一次');
    }
    final List<String> pairs = <String>[];
    for (final String line in raw) {
      final String head = line.split(';').first.trim();
      if (head.contains('=')) pairs.add(head);
    }
    return pairs.join('; ');
  }

  // ---------- 分 享 链 ----------

  /// 14 §2.1：分享 token
  Future<({String stoken, String title, String firstFid})> shareToken({
    required String pwdId,
    String passcode = '',
  }) async {
    final Response<dynamic> r = await _dio.post<dynamic>(
      '$apiBase/1/clouddrive/share/sharepage/token',
      queryParameters: _query,
      data: <String, Object?>{'pwd_id': pwdId, 'passcode': passcode},
    );
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code != 0) {
      // 41008 需要提取码 / 41009 提取码错 / 41010 已失效 / 31001 登录失效
      if (code == 41008) throw const ResolveException(hint: '这个分享要提取码');
      if (code == 41009) throw const ResolveException(hint: '提取码不对');
      if (code == 41010) throw const ResolveException(hint: '这个分享已经失效了');
      throwBizCode(code, authCodes: <int>{31001}, what: '夸克');
    }
    final Map<String, Object?> data = _asMap(body['data']);
    return (
      stoken: '${data['stoken'] ?? ''}',
      title: '${data['title'] ?? ''}',
      firstFid: '${data['first_fid'] ?? ''}',
    );
  }

  /// 14 §2.2：分享目录（pdir_fid 是字符串，"0" 表示根）
  Future<List<RemoteEntry>> shareDetail({
    required String pwdId,
    required String stoken,
    String pdirFid = '0',
    int page = 1,
    int size = 50,
  }) async {
    final Response<dynamic> r = await _dio.get<dynamic>(
      '$apiBase/1/clouddrive/share/sharepage/detail',
      queryParameters: <String, String>{
        ..._query,
        'pwd_id': pwdId,
        'stoken': stoken,
        'pdir_fid': pdirFid,
        'force': '0',
        '_page': '$page',
        '_size': '$size',
        '_fetch_banner': '0',
        '_fetch_share': '0',
      },
    );
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code != 0) throwBizCode(code, authCodes: <int>{31001}, what: '夸克');
    final Map<String, Object?> data = _asMap(body['data']);
    final List<Object?> list = _asList(data['list']);
    return list.map((Object? raw) {
      final Map<String, Object?> m = _asMap(raw);
      final bool isDir = m['dir'] == true || _int(m['file_type']) == 0;
      return RemoteEntry(
        id: '${m['fid'] ?? ''}',
        name: '${m['file_name'] ?? ''}',
        isDir: isDir,
        size: _int(m['size']),
        mtime: m['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(_int(m['updated_at'])),
        extra: <String, String>{
          if (m['share_fid_token'] != null) 'share_fid_token': '${m['share_fid_token']}',
        },
      );
    }).toList();
  }

  /// 14 §2.3：拿直链（10 分钟有效，播放时要带同一份 Cookie + Referer）
  Future<ResolvedUrl> shareDownload({
    required String pwdId,
    required String stoken,
    required String fid,
  }) async {
    final Response<dynamic> r = await _dio.post<dynamic>(
      '$apiBase/1/clouddrive/share/sharepage/download',
      queryParameters: _query,
      data: <String, Object?>{
        'fids': <String>[fid],
        'pwd_id': pwdId,
        'stoken': stoken,
      },
    );
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code != 0) throwBizCode(code, authCodes: <int>{31001}, what: '夸克');
    final List<Object?> list = _asList(body['data']);
    if (list.isEmpty) throw const ResolveException(hint: '夸克没给直链，可能是分享失效了');
    final Map<String, Object?> first = _asMap(list.first);
    final String url = '${first['download_url'] ?? ''}';
    if (url.isEmpty) throw const ResolveException(hint: '夸克没给直链');
    final int expiresAt = _int(first['expires_at']);
    return ResolvedUrl(
      url: url,
      headers: <String, String>{
        'Cookie': cookie,
        'Referer': 'https://pan.quark.cn/',
        'User-Agent': kDesktopUa,
      },
      resolver: 'quark',
      expiresAt: expiresAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
          : DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  // ---------- 接 口 实 现 ----------

  @override
  Future<List<RemoteEntry>> list(String path) async {
    if (_pwdId.isEmpty || _stoken.isEmpty) {
      throw const ResolveException(
        hint: '夸克账号已经建好了，但还没绑定分享链接；等登录那一轮接上就这么用',
      );
    }
    // path 形如 `/fid`；根目录用 "0"
    final String fid = path.replaceAll('/', '').trim();
    return shareDetail(
      pwdId: _pwdId,
      stoken: _stoken,
      pdirFid: fid.isEmpty ? '0' : fid,
    );
  }

  @override
  Future<ResolvedUrl> resolve(RemoteEntry entry) async {
    if (entry.isDir) throw const ResolveException(hint: '目录没法直接播，先点进去');
    if (_pwdId.isEmpty || _stoken.isEmpty) {
      throw const ResolveException(hint: '夸克还没绑定分享链接');
    }
    return shareDownload(pwdId: _pwdId, stoken: _stoken, fid: entry.id);
  }

  @override
  Future<void> saveCredential() async {
    await store.put(credKey, cookie);
  }

  @override
  Future<void> clearCredential() async {
    await store.delete(credKey);
  }

  static String _uuid() {
    final Random rnd = Random();
    String hex(int n) => List<String>.generate(
          n,
          (int _) => rnd.nextInt(16).toRadixString(16),
        ).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${hex(4)}-${hex(12)}';
  }

  static Map<String, Object?> _asMap(Object? raw) {
    if (raw is Map) return raw.cast<String, Object?>();
    if (raw is String && raw.isNotEmpty) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    }
    return <String, Object?>{};
  }

  static List<Object?> _asList(Object? raw) {
    if (raw is List) return raw;
    if (raw is Map) {
      final List<Object?> out = <Object?>[];
      raw.forEach((Object? k, Object? v) => out.add(v));
      return out;
    }
    return const <Object?>[];
  }

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? 0;
  }
}
