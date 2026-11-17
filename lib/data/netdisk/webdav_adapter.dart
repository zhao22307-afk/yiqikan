/// WebDAV 适配器（14 §7）。
///
/// 只做四件事：PROPFIND 列目录、207 解析、HEAD 探元信息、GET 带 Range 播放。
/// 三个容易翻车的点，都写进了解析器的注释与单测：
/// 1. `resourcetype` **空标签**表示文件，含 `<D:collection/>` 才是目录；
/// 2. `href` 是 URL 编码的，中文名要 `Uri.decodeComponent`；
/// 3. 第一条 response 通常是「查询目录自己」，要跳过。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/redact.dart';
import '../../domain/resolver.dart';
import '../local/secure_store.dart';
import 'netdisk_adapter.dart';

/// 207 Multi-Status 解析器（纯函数，便于用 fixture 单测）
class WebDavParser {
  const WebDavParser._();

  static final RegExp _responseRe =
      RegExp(r'<(?:\w+:)?response\b[^>]*>(.*?)</(?:\w+:)?response>', dotAll: true);
  static final RegExp _hrefRe =
      RegExp(r'<(?:\w+:)?href\b[^>]*>(.*?)</(?:\w+:)?href>', dotAll: true);
  static final RegExp _displayRe =
      RegExp(r'<(?:\w+:)?displayname\b[^>]*>(.*?)</(?:\w+:)?displayname>', dotAll: true);
  static final RegExp _lengthRe =
      RegExp(r'<(?:\w+:)?getcontentlength\b[^>]*>(.*?)</(?:\w+:)?getcontentlength>', dotAll: true);
  static final RegExp _typeRe =
      RegExp(r'<(?:\w+:)?getcontenttype\b[^>]*>(.*?)</(?:\w+:)?getcontenttype>', dotAll: true);
  static final RegExp _mtimeRe =
      RegExp(r'<(?:\w+:)?getlastmodified\b[^>]*>(.*?)</(?:\w+:)?getlastmodified>', dotAll: true);
  static final RegExp _ritemRe =
      RegExp(r'<(?:\w+:)?resourcetype\b[^>]*>(.*?)</(?:\w+:)?resourcetype>', dotAll: true);

  /// [requestPath] 用来跳过「目录自己」那条；传 null 就不跳过。
  static List<RemoteEntry> parse(String xml, {String? requestPath}) {
    final String wanted = requestPath == null ? '' : _norm(_decodePath(requestPath));
    final List<RemoteEntry> out = <RemoteEntry>[];
    bool skippedSelf = false;
    int idx = -1;

    for (final RegExpMatch m in _responseRe.allMatches(xml)) {
      idx++;
      final String block = m.group(1) ?? '';
      final String rawHref = _first(_hrefRe, block);
      if (rawHref.isEmpty) continue;

      // href 可能是绝对 URL（有些服务端会回 http://host/dav/a.mp4），只取 path 部分
      final String decoded = _decodePath(rawHref);
      final String path = _normEncoded(decoded);
      // 第一条 response 通常是「查询目录自己」。
      // 判据（按可靠度）：
      //   a) href 与请求路径相同（最准）
      //   b) 它就是第一块，而且是个 collection（服务端把 href 写成 /dav/ 而请求是 / 时靠这条）
      final String rtype = _first(_ritemRe, block);
      final bool isDirEntry = rtype.toLowerCase().contains('collection');
      if (!skippedSelf) {
        if (wanted.isNotEmpty && path == wanted) {
          skippedSelf = true;
          continue;
        }
        if (wanted.isNotEmpty && out.isEmpty && isDirEntry && idx == 0) {
          skippedSelf = true;
          continue;
        }
      }

      // resourcetype：空标签 = 文件；含 collection = 目录
      final bool isDir = isDirEntry;

      String name = _unescape(_first(_displayRe, block)).trim();
      if (name.isEmpty) {
        name = _baseName(path);
      }

      final int size = int.tryParse(_first(_lengthRe, block).trim()) ?? 0;
      final String ctype = _unescape(_first(_typeRe, block)).trim();
      final DateTime? mtime = _parseHttpDate(_first(_mtimeRe, block).trim());

      final Map<String, String> extra = <String, String>{};
      if (ctype.isNotEmpty) extra['content-type'] = ctype;
      if (isDir) extra['type'] = 'collection';

      out.add(RemoteEntry(
        id: path,
        name: name,
        isDir: isDir,
        size: size,
        mtime: mtime,
        extra: extra,
      ));
    }
    return out;
  }

  static String _first(RegExp re, String s) {
    final RegExpMatch? m = re.firstMatch(s);
    return m == null ? '' : (m.group(1) ?? '');
  }

  /// href 解码：先去掉绝对 URL 的 scheme://host，再 decodeComponent。
  ///
  /// 注意：不能对整串直接 `Uri.decode`——`+` 会被当成空格，文件名里的 `+` 会变形。
  static String _decodePath(String href) {
    String s = href.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      final Uri? uri = Uri.tryParse(s);
      if (uri != null) s = uri.path.isEmpty ? '/' : uri.path;
    }
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s; // 已经是明文（服务端没编码）就别硬解
    }
  }

  /// 去掉末尾斜杠、保证以 / 开头
  static String _norm(String path) {
    String p = path.trim();
    if (p.isEmpty) return '/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static String _normEncoded(String path) => _norm(path);

  static String _baseName(String path) {
    final String p = _norm(path);
    final int i = p.lastIndexOf('/');
    return i <= 0 ? p : p.substring(i + 1);
  }

  static String _unescape(String s) {
    if (!s.contains('&')) return s;
    return s
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  static DateTime? _parseHttpDate(String s) {
    if (s.isEmpty) return null;
    try {
      return _httpDate(s);
    } catch (_) {
      return null;
    }
  }

  /// 只认 RFC 1123 一种（WebDAV 服务端都用这个），解析不了就当没有
  static DateTime _httpDate(String s) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final RegExp re = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})');
    final RegExpMatch? m = re.firstMatch(s);
    if (m == null) throw const FormatException('bad http-date');
    final int mon = months.indexOf(m.group(2) ?? '') + 1;
    if (mon == 0) throw const FormatException('bad month');
    return DateTime.utc(
      int.parse(m.group(3) ?? '1970'),
      mon,
      int.parse(m.group(1) ?? '1'),
      int.parse(m.group(4) ?? '0'),
      int.parse(m.group(5) ?? '0'),
      int.parse(m.group(6) ?? '0'),
    );
  }
}

/// WebDAV 适配器：列目录 / 拿直链
class WebDavAdapter extends NetdiskAdapter {
  WebDavAdapter({
    required super.account,
    required this.username,
    required this.password,
    required this.store,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              // PROPFIND / 207 都得自己判，禁止 dio 把 4xx 抛成自己的异常
              validateStatus: (int? code) => code != null && code < 500,
            ));

  @override
  NetdiskKind get kind => NetdiskKind.webdav;

  final String username;
  final String password;
  final SecureStore store;
  final Dio _dio;

  String get _base {
    final String b = account.endpoint.trim();
    if (b.isEmpty) throw const InvalidSourceException('WebDAV 地址是空的');
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /// entry.id 是服务器返回的 href（可能带 `%XX`、可能已经含 endpoint 自己的路径段，
  /// 比如 endpoint 是 `/dav/`、href 是 `/dav/a.mp4`）。这里把它还原成「相对 endpoint 的路径」，
  /// 否则会拼出 `/dav/dav/a.mp4` 这种一眼假的地址。
  String _pathUnderBase(String href) {
    String p = href;
    final int schemeAt = p.indexOf('://');
    if (schemeAt >= 0) {
      final int slash = p.indexOf('/', schemeAt + 3);
      p = slash >= 0 ? p.substring(slash) : '/';
    }
    // href 可能是 `%E4%B8%AD` 这种编码，也可能服务器直接给了明文（甚至带裸 %），
    // 解不开就按明文用，别让一个奇怪的字符把整个解析打断。
    try {
      p = Uri.decodeComponent(p);
    } on Object {
      // 解不开（可能本来就是明文，或者带裸 %）：保留原样
    }
    final Uri base = Uri.parse('$_base/');
    final String basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    if (basePath.isNotEmpty && p.startsWith('$basePath/')) {
      p = p.substring(basePath.length);
    } else if (basePath.isNotEmpty && p == basePath) {
      p = '/';
    }
    return p.startsWith('/') ? p : '/$p';
  }

  Map<String, String> _headers({bool depthOne = true}) => <String, String>{
        'Authorization': _authHeader,
        'Depth': depthOne ? '1' : '0',
        'Content-Type': 'application/xml; charset=utf-8',
      };

  static const String _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:getcontentlength/><d:getcontenttype/>'
      '<d:getlastmodified/><d:resourcetype/>'
      '</d:prop></d:propfind>';

  @override
  Future<bool> verify() async {
    final Response<dynamic> r = await _request(
      'PROPFIND',
      '$_base/',
      depthOne: false,
    );
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw AuthExpiredException(cause: 'WebDAV ${r.statusCode}');
    }
    return r.statusCode == 207 || r.statusCode == 200;
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final String p = path.trim().isEmpty ? '/' : path.trim();
    final String url = '$_base${p.startsWith('/') ? p : '/$p'}';
    final Response<dynamic> r = await _request('PROPFIND', url);
    if (r.statusCode == 401) {
      throw const AuthExpiredException(cause: 'WebDAV PROPFIND 401');
    }
    if (r.statusCode != 207) {
      throw ResolveException(
        cause: 'WebDAV PROPFIND ${r.statusCode} ${redactUrl(url)}',
        hint: '服务端没回 207，确认地址指向的是 WebDAV 根目录',
      );
    }
    final String body = r.data is String ? r.data as String : jsonEncode(r.data);
    final List<RemoteEntry> all = WebDavParser.parse(body, requestPath: p);
    // 目录在前、同类型按名字排（浏览页直接拿现成顺序）
    all.sort((RemoteEntry a, RemoteEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return all;
  }

  @override
  Future<ResolvedUrl> resolve(RemoteEntry entry) async {
    if (entry.isDir) {
      throw const ResolveException(hint: '目录没法直接播，先点进去');
    }
    // 逐段编码：服务器给的 href 里偶尔带裸 % 或者已经编码过一半，
    // 整串 encodeFull 会抛 Illegal percent encoding，分段编码就不会。
    debugPrint('[YQK-WEBDAV] resolve id=${entry.id.length} chars, base=$_base');
    final String rel = _pathUnderBase(entry.id);
    final String encoded = rel.split('/').map(Uri.encodeComponent).join('/');
    final String url = '$_base$encoded';
    // 只打脱敏地址：真 WebDAV 直链可能带 ?sign=，网盘必然带 auth_key
    debugPrint('[YQK-WEBDAV] resolve -> ${redactUrl(url)}');
    return ResolvedUrl(
      url: url,
      headers: <String, String>{'Authorization': _authHeader},
      resolver: 'webdav',
      lastUrlUpdate: DateTime.now(),
    );
  }

  Future<Response<dynamic>> _request(
    String method,
    String url, {
    bool depthOne = true,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      return await _dio.request<dynamic>(
        url,
        data: method == 'PROPFIND' ? _propfindBody : null,
        options: Options(
          method: method,
          headers: <String, String>{..._headers(depthOne: depthOne), ...?extraHeaders},
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      final Object? inner = e.error;
      if (inner is AuthExpiredException) rethrow;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw RequestTimeoutException(cause: e);
      }
      if (e.type == DioExceptionType.connectionError) {
        throw NetworkException(cause: e);
      }
      // 有状态码就交给上层按码判断
      final Response<dynamic>? resp = e.response;
      if (resp != null) return resp;
      throw NetworkException(cause: e);
    }
  }

  /// 凭据只进 SecureStore（key 见 03 §5：`cred_<id>`）
  @override
  Future<void> saveCredential() async {
    await store.put('cred_webdav_user', username);
    await store.put('cred_webdav_pass', password);
  }

  @override
  Future<void> clearCredential() async {
    await store.delete('cred_webdav_user');
    await store.delete('cred_webdav_pass');
  }
}
