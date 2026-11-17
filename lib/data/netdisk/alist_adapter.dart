/// AList 适配器（14 §8）。
///
/// 三个必须按原样处理的点：
/// - `Authorization: {token}` **不带 Bearer**；401 时再试一次带 Bearer（v3.30+ 的差异）。
/// - `/api/fs/get` 的 `raw_url` 只在 provider 支持直链时才有，否则回落 `url`（AList 代理）。
///   两个都空才算失败——**不能**因为 raw_url 空就报错。
/// - `code` 字段：200 成功 / 401 未登录 / 500 其它错误，不能只看 HTTP 状态码。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/redact.dart';
import '../../domain/resolver.dart';
import '../local/secure_store.dart';
import 'netdisk_adapter.dart';

/// `/api/fs/get` 的解析结果。raw_url 为空但 url 有值 → 走代理。
class AlistResolved {
  const AlistResolved({required this.url, required this.viaRaw, required this.provider});

  final String url;

  /// true = 用的是 raw_url（存储端原始地址）；false = 用的是 AList 代理地址
  final bool viaRaw;
  final String provider;
}

/// 纯函数解析，单测直接喂 fixture。
class AlistParser {
  const AlistParser._();

  static void _checkCode(Map<String, dynamic> body, String what) {
    final Object? code = body['code'];
    final int c = code is int ? code : int.tryParse('$code') ?? 0;
    if (c == 200) return;
    if (c == 401) {
      throw AuthExpiredException(cause: '$what 返回 code=401');
    }
    throw ResolveException(
      cause: '$what 返回 code=$c message=${body['message'] ?? ''}',
      hint: 'AList 那边报错了，去它的管理页看看存储挂载还正常吗',
    );
  }

  /// 列目录：`data.content[]`
  static List<RemoteEntry> parseList(Map<String, dynamic> body) {
    _checkCode(body, '/api/fs/list');
    final Object? data = body['data'];
    if (data is! Map) {
      throw const ParseException('/api/fs/list 的 data');
    }
    final Object? content = data['content'];
    if (content == null) return <RemoteEntry>[];
    if (content is! List) throw const ParseException('/api/fs/list 的 content');

    final List<RemoteEntry> out = <RemoteEntry>[];
    for (final Object? raw in content) {
      if (raw is! Map) continue;
      final Map<String, dynamic> m = raw.cast<String, dynamic>();
      final String name = (m['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final bool isDir = m['is_dir'] == true;
      final int size = (m['size'] is int) ? m['size'] as int : 0;
      final String sign = (m['sign'] ?? '').toString();
      out.add(RemoteEntry(
        id: name, // AList 用「父路径 + name」定位，id 就是 name，路径在适配器里拼
        name: name,
        isDir: isDir,
        size: size,
        mtime: DateTime.tryParse((m['modified'] ?? '').toString()),
        thumb: (m['thumb'] ?? '').toString().isEmpty ? null : m['thumb'].toString(),
        extra: <String, String>{if (sign.isNotEmpty) 'sign': sign},
      ));
    }
    out.sort((RemoteEntry a, RemoteEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  /// 拿直链：优先 raw_url，空则 url，两个都空 → ResolveException
  static AlistResolved parseGet(Map<String, dynamic> body) {
    _checkCode(body, '/api/fs/get');
    final Object? data = body['data'];
    if (data is! Map) throw const ParseException('/api/fs/get 的 data');
    final Map<String, dynamic> m = data.cast<String, dynamic>();
    final String rawUrl = (m['raw_url'] ?? '').toString().trim();
    final String proxyUrl = (m['url'] ?? '').toString().trim();
    final String provider = (m['provider'] ?? '').toString();
    if (rawUrl.isNotEmpty) {
      return AlistResolved(url: rawUrl, viaRaw: true, provider: provider);
    }
    if (proxyUrl.isNotEmpty) {
      return AlistResolved(url: proxyUrl, viaRaw: false, provider: provider);
    }
    throw ResolveException(
      cause: 'raw_url 与 url 都为空（provider=$provider）',
      hint: '这个存储可能不支持直链，换个文件试试',
    );
  }
}

class AlistAdapter extends NetdiskAdapter {
  AlistAdapter({
    required super.account,
    required this.token,
    required this.store,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              validateStatus: (int? code) => code != null && code < 500,
            ));

  @override
  NetdiskKind get kind => NetdiskKind.alist;

  final String token;
  final SecureStore store;
  final Dio _dio;

  /// AList 新版本（v3.30+）要 Bearer，老版本不要；401 时自动换一次并记住。
  bool _bearer = false;

  String get _base {
    final String b = account.endpoint.trim();
    if (b.isEmpty) throw const InvalidSourceException('AList 地址是空的');
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  Map<String, String> get _headers => <String, String>{
        'Authorization': _bearer ? 'Bearer $token' : token,
        'Content-Type': 'application/json',
      };

  @override
  Future<bool> verify() async {
    final Response<dynamic> r = await _post('/api/fs/list', <String, dynamic>{
      'path': '/',
      'password': '',
      'page': 1,
      'per_page': 1,
      'refresh': false,
    });
    final int code = _codeOf(r.data);
    if (code == 401) throw const AuthExpiredException(cause: 'AList 401');
    return code == 200;
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final String p = _normPath(path);
    final Response<dynamic> r = await _post('/api/fs/list', <String, dynamic>{
      'path': p,
      'password': '',
      'page': 1,
      'per_page': 200,
      'refresh': false,
    });
    return AlistParser.parseList(_asMap(r.data, '/api/fs/list'));
  }

  @override
  Future<ResolvedUrl> resolve(RemoteEntry entry) async {
    if (entry.isDir) {
      throw const ResolveException(hint: '目录没法直接播，先点进去');
    }
    final String p = entry.extra['path'] ?? '/${entry.id}';
    final Response<dynamic> r = await _post('/api/fs/get', <String, dynamic>{
      'path': p,
      'password': '',
    });
    final AlistResolved got = AlistParser.parseGet(_asMap(r.data, '/api/fs/get'));
    // AList 的 raw_url 带存储端鉴权；代理地址则依赖 AList 自己的会话，
    // 两种都把 Authorization 一起带上（多带无害，少带必 403）。
    return ResolvedUrl(
      url: got.url,
      headers: <String, String>{'Authorization': _bearer ? 'Bearer $token' : token},
      resolver: got.viaRaw ? 'alist-raw' : 'alist-proxy',
      lastUrlUpdate: DateTime.now(),
    );
  }

  Future<Response<dynamic>> _post(String path, Map<String, dynamic> body) async {
    Future<Response<dynamic>> once() => _dio.post<dynamic>(
          '$_base$path',
          data: body,
          options: Options(headers: _headers, responseType: ResponseType.plain),
        );
    try {
      Response<dynamic> r = await once();
      if (_codeOf(r.data) == 401) {
        // 401 有两种可能：token 真过期；或这版 AList 要 Bearer
        final bool wasBearer = _bearer;
        _bearer = !_bearer;
        r = await once();
        final int c2 = _codeOf(r.data);
        if (c2 == 200) return r;
        _bearer = wasBearer; // 两种都不行 → 是凭据过期，不是前缀问题
        throw AuthExpiredException(cause: 'AList $path 401（Bearer=$wasBearer/$_bearer）');
      }
      return r;
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

  Map<String, dynamic> _asMap(Object? data, String what) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final Object? decoded = _jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // 落到下面抛 ParseException
      }
    }
    throw ParseException(what, cause: '返回不是 JSON 对象：${redactUrl(_base)}');
  }

  int _codeOf(Object? data) {
    Object? src = data;
    if (src is String) {
      try {
        src = _jsonDecode(src);
      } catch (_) {
        return 0;
      }
    }
    if (src is Map) {
      final Object? code = src['code'];
      return code is int ? code : int.tryParse('$code') ?? 0;
    }
    return 0;
  }

  static Object? _jsonDecode(String s) => jsonDecode(s);

  static String _normPath(String path) {
    String p = path.trim();
    if (p.isEmpty) return '/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  @override
  Future<void> saveCredential() async {
    await store.put('cred_alist_token', token);
  }

  @override
  Future<void> clearCredential() async {
    await store.delete('cred_alist_token');
  }
}
