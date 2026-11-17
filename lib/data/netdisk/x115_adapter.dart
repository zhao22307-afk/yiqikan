/// 115 网盘（14 §3）：Cookie 四段校验 → share/snap → files → downurl。
///
/// downurl 返回的是 AES-128-CBC 加密串。文档 04 §10.3 写 iv=key，
/// 实际另有实现把前 16 字节当 iv；这里写成「A 先 B 后」的探测：
/// 谁能解出含 `"state": true` 的合法 JSON 就用谁，第一次跑通后回填文档。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart' as pc;

import '../../core/errors/app_exception.dart';
import '../../domain/resolver.dart';
import '../local/secure_store.dart';
import 'netdisk_adapter.dart';
import 'netdisk_http.dart';

/// 解密探测的结果：用哪种方案 + 解出来的明文
class CipherProbe {
  const CipherProbe({required this.scheme, required this.plain});

  /// `A` = iv 固定取 key；`B` = iv 取密文前 16 字节
  final String scheme;
  final String plain;
}

class X115Adapter extends NetdiskAdapter {
  X115Adapter({
    required super.account,
    required this.cookie,
    required this.store,
    Dio? dio,
  }) : _dio = dio ??
            newNetdiskDio(baseHeaders: <String, String>{
              'Cookie': cookie,
              'Referer': 'https://115.com/',
              'User-Agent': kDesktopUa,
            });

  static const String webBase = 'https://webapi.115.com';
  static const String appBase = 'https://proapi.115.com';
  static const String credKey = 'cred_115_cookie';

  /// 115 的 AES key 是历史固定值
  static const String aesKey = '1234567890123456';

  /// Cookie 必须有的四段（缺哪个报哪个）
  static const List<String> cookieFields = <String>['UID', 'CID', 'SEID', 'KID'];

  final String cookie;
  final SecureStore store;
  final Dio _dio;

  @override
  NetdiskKind get kind => NetdiskKind.pan115;

  /// 返回缺失字段名列表；空列表 = 四段齐
  static List<String> missingCookieFields(String raw) {
    final List<String> missing = <String>[];
    for (final String k in cookieFields) {
      final RegExp re = RegExp('(^|;\\s*)$k=', caseSensitive: false);
      if (!re.hasMatch(raw)) missing.add(k);
    }
    return missing;
  }

  /// 115 的报错文案是照抄原 App 的（13 §C 里对过）
  static String cookieErrorText(List<String> missing) {
    if (missing.length >= 4) return 'Cookie 里没找到登录信息，请重新登录';
    return 'Cookie 缺少 ${missing.join(' / ')}，请重新登录';
  }

  @override
  Future<bool> verify() async {
    final List<String> missing = missingCookieFields(cookie);
    if (missing.isNotEmpty) {
      throw AuthExpiredException(hint: cookieErrorText(missing));
    }
    final Response<dynamic> r =
        await _dio.get<dynamic>('$webBase/files', queryParameters: <String, String>{
      'aid': '1',
      'cid': '0',
      'offset': '0',
      'limit': '1',
    });
    if ((r.statusCode ?? 0) >= 400) throwHttpStatus(r.statusCode, what: '115');
    final Map<String, Object?> body = _asMap(r.data);
    if (body['state'] == false) {
      throw const AuthExpiredException(hint: '115 说登录失效了，重新粘一次 Cookie');
    }
    return true;
  }

  /// 14 §3.4：分享快照（state 是布尔，不是数字）
  Future<List<RemoteEntry>> shareSnap({
    required String shareCode,
    String receiveCode = '',
    String cid = '0',
  }) async {
    final Response<dynamic> r = await _dio.post<dynamic>(
      '$webBase/share/snap',
      data: <String, String>{
        'share_code': shareCode,
        'receive_code': receiveCode,
        'cid': cid,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final Map<String, Object?> body = _asMap(r.data);
    if (body['state'] != true) {
      final String msg = '${body['error'] ?? body['msg'] ?? ''}';
      if (msg.contains('登录') || msg.contains('cookie')) {
        throw const AuthExpiredException();
      }
      throw ResolveException(hint: msg.isEmpty ? '115 打不开这个分享' : msg);
    }
    final Map<String, Object?> data = _asMap(body['data']);
    final List<Object?> list = _asList(data['list']);
    return list.map((Object? raw) {
      final Map<String, Object?> m = _asMap(raw);
      return RemoteEntry(
        id: '${m['fid'] ?? ''}',
        name: '${m['n'] ?? ''}',
        isDir: '${m['cid'] ?? ''}' == '0' && (m['sha'] ?? '') == '',
        size: _int(m['s']),
        extra: <String, String>{
          if (m['cid'] != null) 'cid': '${m['cid']}',
          if (m['sha'] != null) 'sha': '${m['sha']}',
        },
      );
    }).toList();
  }

  /// 14 §3.5：拿 pickcode（真正的地址要再换一次）
  Future<String> shareDownloadPickCode({
    required String shareCode,
    required String receiveCode,
    required String fileId,
  }) async {
    final Response<dynamic> r = await _dio.get<dynamic>(
      '$webBase/share/download',
      queryParameters: <String, String>{
        'share_code': shareCode,
        'receive_code': receiveCode,
        'file_id': fileId,
      },
    );
    final Map<String, Object?> body = _asMap(r.data);
    if (body['state'] != true) {
      throw const ResolveException(hint: '115 没给下载凭据，可能分享失效了');
    }
    final Map<String, Object?> data = _asMap(body['data']);
    final Map<String, Object?> url = _asMap(data['url']);
    final String pick = '${data['pick_code'] ?? url['pick_code'] ?? ''}';
    if (pick.isEmpty) throw const ResolveException(hint: '115 没给 pickcode');
    return pick;
  }

  /// 14 §3.6：用 pickcode 换真地址（返回加密串）
  Future<String> downUrlCipher(String pickCode) async {
    final Response<dynamic> r = await _dio.post<dynamic>(
      '$appBase/app/chrome/downurl',
      data: <String, String>{'data': pickCode},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final Map<String, Object?> body = _asMap(r.data);
    final String cipher = '${body['data'] ?? ''}';
    if (cipher.isEmpty || cipher == 'null') {
      throw const ResolveException(hint: '115 没返回下载地址');
    }
    return cipher;
  }

  /// 「A 先 B 后」的解密探测（A 失败或长度不整就试 B）
  static CipherProbe? probeDecrypt(String cipherB64) {
    final Uint8List raw;
    try {
      raw = base64Decode(cipherB64);
    } on Object {
      return null;
    }
    final List<int> key = utf8.encode(aesKey);

    String? tryScheme(String scheme, Uint8List iv, Uint8List body) {
      try {
        final pc.CBCBlockCipher cbc = pc.CBCBlockCipher(pc.AESEngine());
        cbc.init(false, pc.ParametersWithIV(pc.KeyParameter(Uint8List.fromList(key)), iv));
        final Uint8List out = Uint8List(body.length);
        for (int i = 0; i < body.length; i += 16) {
          cbc.processBlock(body, i, out, i);
        }
        final Uint8List unpadded = _stripPkcs7(out);
        final String text = utf8.decode(unpadded, allowMalformed: false);
        if (text.contains('"state": true') || text.contains('"state":true')) {
          return text;
        }
      } on Object {
        return null;
      }
      return null;
    }

    if (raw.length % 16 == 0 && raw.length > 16) {
      final String? a = tryScheme('A', Uint8List.fromList(key), raw);
      if (a != null) return CipherProbe(scheme: 'A', plain: a);
    }
    if (raw.length > 32 && (raw.length - 16) % 16 == 0) {
      final String? b = tryScheme(
        'B',
        raw.sublist(0, 16),
        raw.sublist(16),
      );
      if (b != null) return CipherProbe(scheme: 'B', plain: b);
    }
    return null;
  }

  static Uint8List _stripPkcs7(Uint8List data) {
    if (data.isEmpty) return data;
    final int pad = data.last;
    if (pad <= 0 || pad > 16 || pad > data.length) return data;
    return data.sublist(0, data.length - pad);
  }

  /// 解密后从 JSON 里取出 `data[fileId].url.url`
  static String? pickUrlFromPlain(String plain, String fileId) {
    try {
      final Map<String, Object?> body = _asMap(jsonDecode(plain));
      final Map<String, Object?> data = _asMap(body['data']);
      final Map<String, Object?> one = _asMap(data[fileId] ?? (data.isEmpty ? null : data.values.first));
      final Map<String, Object?> url = _asMap(one['url']);
      final String u = '${url['url'] ?? one['url'] ?? ''}';
      return u.isEmpty ? null : u;
    } on Object {
      return null;
    }
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final String cid = path.replaceAll('/', '').trim();
    final Response<dynamic> r =
        await _dio.get<dynamic>('$webBase/files', queryParameters: <String, String>{
      'aid': '1',
      'cid': cid.isEmpty ? '0' : cid,
      'offset': '0',
      'limit': '100',
      'show_dir': '1',
    });
    final Map<String, Object?> body = _asMap(r.data);
    if (body['state'] == false) {
      throw const AuthExpiredException(hint: '115 说登录失效了，重新粘一次 Cookie');
    }
    final List<Object?> list = _asList(body['data']);
    return list.map((Object? raw) {
      final Map<String, Object?> m = _asMap(raw);
      return RemoteEntry(
        id: '${m['fid'] ?? ''}',
        name: '${m['n'] ?? ''}',
        isDir: '${m['cid'] ?? ''}' == '0' && (m['sha'] ?? '') == '',
        size: _int(m['s']),
        extra: <String, String>{'pick_code': '${m['pc'] ?? ''}'},
      );
    }).toList();
  }

  @override
  Future<ResolvedUrl> resolve(RemoteEntry entry) async {
    if (entry.isDir) throw const ResolveException(hint: '目录没法直接播，先点进去');
    final String pick = entry.extra['pick_code'] ?? '';
    if (pick.isEmpty) throw const ResolveException(hint: '115 这条没有 pickcode');
    final String cipher = await downUrlCipher(pick);
    final CipherProbe? probe = probeDecrypt(cipher);
    if (probe == null) {
      throw const ResolveException(
        hint: '115 的下载地址解不开（A/B 两种 iv 都试过了），把这次密文留着按 04 §10.3 再对一次',
      );
    }
    final String? url = pickUrlFromPlain(probe.plain, entry.id);
    if (url == null) throw const ResolveException(hint: '115 解开了但没有地址');
    return ResolvedUrl(
      url: url,
      headers: <String, String>{
        'Cookie': cookie,
        'Referer': 'https://115.com/',
        'User-Agent': kDesktopUa,
      },
      resolver: '115',
      lastUrlUpdate: DateTime.now(),
    );
  }

  @override
  Future<void> saveCredential() async => store.put(credKey, cookie);

  @override
  Future<void> clearCredential() async => store.delete(credKey);

  static Map<String, Object?> _asMap(Object? raw) {
    if (raw is Map) return raw.cast<String, Object?>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final Object? d = jsonDecode(raw);
        if (d is Map) return d.cast<String, Object?>();
      } on Object {
        return <String, Object?>{};
      }
    }
    return <String, Object?>{};
  }

  static List<Object?> _asList(Object? raw) => raw is List ? raw : const <Object?>[];

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? 0;
  }
}
