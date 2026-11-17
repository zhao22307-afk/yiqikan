/// Emby 适配器（14 §6）。
///
/// 三个关键点：
/// - `X-Emby-Authorization` 里的 **DeviceId 必须持久化**：每次登录都换 UUID 的话，
///   服务器会当成新设备，播放进度/收藏全丢、设备列表越堆越多（Emby 用户的经典投诉）。
///   这里第一次生成后就写进 SecureStore，之后一直复用。
/// - `Pw` 是明文密码，Emby 自己 hash。
/// - 播放优先 `/Videos/{id}/stream?Static=true`（直出原文件），失败才谈转码。
library;

import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../domain/resolver.dart';
import '../../core/errors/app_exception.dart';
import '../local/secure_store.dart';
import 'netdisk_adapter.dart';

/// Emby 的纯函数解析部分（fixture 单测直接打这里）
class EmbyParser {
  const EmbyParser._();

  /// `/Users/AuthenticateByName` 的返回
  static EmbyAuth parseAuth(Map<String, dynamic> body) {
    final Object? user = body['User'];
    if (user is! Map) throw const ParseException('Emby 登录返回的 User');
    final Map<String, dynamic> u = user.cast<String, dynamic>();
    final String userId = (u['Id'] ?? '').toString();
    final String token = (body['AccessToken'] ?? '').toString();
    if (userId.isEmpty || token.isEmpty) {
      throw const ParseException('Emby 登录返回的 Id/AccessToken');
    }
    return EmbyAuth(
      userId: userId,
      userName: (u['Name'] ?? '').toString(),
      accessToken: token,
      serverId: (body['ServerId'] ?? '').toString(),
    );
  }

  /// `/Users/{id}/Items` → 片单
  static List<RemoteEntry> parseItems(Map<String, dynamic> body) {
    final Object? items = body['Items'];
    if (items is! List) throw const ParseException('Emby Items');
    final List<RemoteEntry> out = <RemoteEntry>[];
    for (final Object? raw in items) {
      if (raw is! Map) continue;
      final Map<String, dynamic> m = raw.cast<String, dynamic>();
      final String id = (m['Id'] ?? '').toString();
      final String name = (m['Name'] ?? '').toString();
      if (id.isEmpty || name.isEmpty) continue;
      final String type = (m['Type'] ?? '').toString();
      final bool isDir = type == 'Series' || type == 'Season' ||
          type == 'Folder' || type == 'CollectionFolder' || type == 'BoxSet';
      // RunTimeTicks：1 tick = 100ns，除 1e7 得秒
      final int ticks = (m['RunTimeTicks'] is int) ? m['RunTimeTicks'] as int : 0;
      final int seconds = ticks ~/ 10000000;
      final Map<String, dynamic>? userData =
          m['UserData'] is Map ? (m['UserData'] as Map).cast<String, dynamic>() : null;
      final int posTicks =
          (userData?['PlaybackPositionTicks'] is int) ? userData!['PlaybackPositionTicks'] as int : 0;

      String? thumb;
      final Object? tags = m['ImageTags'];
      if (tags is Map && tags['Primary'] != null) {
        thumb = tags['Primary'].toString();
      }

      out.add(RemoteEntry(
        id: id,
        name: name,
        isDir: isDir,
        size: 0,
        thumb: thumb,
        extra: <String, String>{
          'type': type,
          if (seconds > 0) 'duration': '$seconds',
          if (posTicks > 0) 'position': '${posTicks ~/ 10000000}',
          if (m['ProductionYear'] != null) 'year': '${m['ProductionYear']}',
        },
      ));
    }
    out.sort((RemoteEntry a, RemoteEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }
}

class EmbyAuth {
  const EmbyAuth({
    required this.userId,
    required this.userName,
    required this.accessToken,
    required this.serverId,
  });

  final String userId;
  final String userName;
  final String accessToken;
  final String serverId;
}

/// DeviceId 持久化：只生成一次，之后所有登录复用同一个。
class EmbyDevice {
  EmbyDevice(this.store);

  static const String storageKey = 'emby_device_id';

  final SecureStore store;
  String? _cached;

  /// 读已有 DeviceId；没有就生成一个 UUIDv4 并落 SecureStore。
  ///
  /// 返回值前 8 位会打进日志（`[YQK-EMBY] deviceId=xxxxxxxx…`），用来证明两次登录是同一台设备。
  Future<String> ensure() async {
    final String? cached = _cached;
    if (cached != null && cached.isNotEmpty) return cached;
    final String? stored = await store.get(storageKey);
    if (stored != null && stored.length >= 8) {
      _cached = stored;
      return stored;
    }
    final String fresh = _uuidV4();
    await store.put(storageKey, fresh);
    _cached = fresh;
    return fresh;
  }

  static String _uuidV4() {
    final Random rnd = Random.secure();
    final List<int> b = List<int>.generate(16, (int _) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    final String s = b.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
        '${s.substring(16, 20)}-${s.substring(20)}';
  }
}

class EmbyAdapter extends NetdiskAdapter {
  EmbyAdapter({
    required super.account,
    required this.username,
    required this.password,
    required this.store,
    Dio? dio,
  })  : _device = EmbyDevice(store),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              validateStatus: (int? code) => code != null && code < 500,
            ));

  @override
  NetdiskKind get kind => NetdiskKind.emby;

  final String username;
  final String password;
  final SecureStore store;
  final EmbyDevice _device;
  final Dio _dio;

  EmbyAuth? _auth;

  String get _base {
    final String b = account.endpoint.trim();
    if (b.isEmpty) throw const InvalidSourceException('Emby 地址是空的');
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  Future<Map<String, String>> _authHeaders() async {
    final String deviceId = await _device.ensure();
    final String token = _auth?.accessToken ?? (await store.get('cred_emby_token') ?? '');
    final StringBuffer sb = StringBuffer()
      ..write('MediaBrowser Client="Yiqikan", Device="Android", ')
      ..write('DeviceId="$deviceId", Version="1.0.0", ');
    if (token.isNotEmpty) sb.write('Token="$token"');
    final String header = sb.toString().replaceAll(',  ', ', ');
    return <String, String>{
      'X-Emby-Authorization': header,
      if (token.isNotEmpty) 'X-Emby-Token': token,
      'Content-Type': 'application/json',
    };
  }

  @override
  Future<bool> verify() async {
    if (_auth != null) return true;
    final Map<String, String> h = await _authHeaders();
    final Response<dynamic> r = await _send(
      () => _dio.post<dynamic>(
        '$_base/Users/AuthenticateByName',
        data: <String, dynamic>{'Username': username, 'Pw': password},
        options: Options(headers: h),
      ),
    );
    if (r.statusCode == 401) {
      throw const AuthExpiredException(cause: 'Emby 登录 401');
    }
    if (r.statusCode != 200) {
      throw ResolveException(cause: 'Emby 登录 ${r.statusCode}');
    }
    final Map<String, dynamic> body = _asMap(r.data);
    _auth = EmbyParser.parseAuth(body);
    await store.put('cred_emby_token', _auth!.accessToken);
    await store.put('cred_emby_user', username);
    await store.put('cred_emby_pass', password);
    final String deviceId = await _device.ensure();
    // 这条日志是验收证据：两次登录 DeviceId 前 8 位必须一样
    // ignore: avoid_print
    print('[YQK-EMBY] login ok deviceId=${deviceId.substring(0, 8)}… user=${_auth!.userId}');
    return true;
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    await verify();
    final Map<String, String> h = await _authHeaders();
    final String parentId = path.trim().isEmpty ? '0' : path.trim();
    final Response<dynamic> r = await _send(
      () => _dio.get<dynamic>(
        '$_base/Users/${_auth!.userId}/Items',
        queryParameters: <String, dynamic>{
          'ParentId': parentId,
          'IncludeItemTypes': 'Movie,Series,Episode,Folder,BoxSet',
          'Recursive': false,
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'Fields': 'Overview,ProductionYear,RunTimeTicks,MediaSources,ImageTags',
          'Limit': 200,
        },
        options: Options(headers: h),
      ),
    );
    if (r.statusCode == 401) throw const AuthExpiredException(cause: 'Emby Items 401');
    if (r.statusCode != 200) throw ResolveException(cause: 'Emby Items ${r.statusCode}');
    return EmbyParser.parseItems(_asMap(r.data));
  }

  @override
  Future<ResolvedUrl> resolve(RemoteEntry entry) async {
    await verify();
    final String deviceId = await _device.ensure();
    // Static=true：直出原文件，别让服务器转码
    final Uri uri = Uri.parse('$_base/Videos/${entry.id}/stream').replace(
      queryParameters: <String, String>{
        'Static': 'true',
        'api_key': _auth!.accessToken,
        'DeviceId': deviceId,
      },
    );
    return ResolvedUrl(
      url: uri.toString(),
      headers: <String, String>{'X-Emby-Token': _auth!.accessToken},
      resolver: 'emby',
      lastUrlUpdate: DateTime.now(),
    );
  }

  Future<Response<dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw RequestTimeoutException(cause: e);
      }
      if (e.type == DioExceptionType.connectionError) {
        throw NetworkException(cause: e);
      }
      final Response<dynamic>? resp = e.response;
      if (resp != null) return resp;
      throw NetworkException(cause: e);
    }
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    throw const ParseException('Emby 返回');
  }

  @override
  Future<void> saveCredential() async {
    await store.put('cred_emby_user', username);
    await store.put('cred_emby_pass', password);
    if (_auth != null) await store.put('cred_emby_token', _auth!.accessToken);
  }

  @override
  Future<void> clearCredential() async {
    await store.delete('cred_emby_token');
    await store.delete('cred_emby_user');
    await store.delete('cred_emby_pass');
    // DeviceId 不删：这台设备还是这台设备
  }
}
