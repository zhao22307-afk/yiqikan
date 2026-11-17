/// 天翼云盘（14 §5）：COOKIE_LOGIN_USER → ssKey 换 accessToken（1h，提前 5 分钟刷）
/// → listShareDir → getFileDownloadUrl。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/resolver.dart';
import '../local/secure_store.dart';
import 'netdisk_adapter.dart';
import 'netdisk_http.dart';

class TianyiAdapter extends NetdiskAdapter {
  TianyiAdapter({
    required super.account,
    required this.cookie,
    required this.store,
    Dio? dio,
  }) : _dio = dio ??
            newNetdiskDio(baseHeaders: <String, String>{
              'Cookie': cookie,
              'Referer': 'https://cloud.189.cn/',
              'User-Agent': kDesktopUa,
            });

  static const String apiBase = 'https://api.cloud.189.cn';
  static const String credKey = 'cred_tianyi_cookie';
  static const String clientId = '538135150693412';

  /// token 提前 5 分钟刷新（14 §5.1 的坑）
  static const Duration refreshAhead = Duration(minutes: 5);

  final String cookie;
  final SecureStore store;
  final Dio _dio;

  String? _token;
  DateTime? _tokenAt;
  Duration _tokenLife = const Duration(hours: 1);

  @override
  NetdiskKind get kind => NetdiskKind.tianyi;

  /// 从 Cookie 里取 COOKIE_LOGIN_USER（ssKey）
  static String? ssKeyFrom(String raw) {
    final RegExp re =
        RegExp(r'(?:^|;\s*)COOKIE_LOGIN_USER=([^;]+)', caseSensitive: false);
    final RegExpMatch? m = re.firstMatch(raw);
    return m == null ? null : Uri.decodeComponent(m.group(1)!);
  }

  bool get _tokenFresh {
    if (_token == null || _tokenAt == null) return false;
    final DateTime expiresAt = _tokenAt!.add(_tokenLife);
    return DateTime.now().isBefore(expiresAt.subtract(refreshAhead));
  }

  /// 14 §5.1：用 ssKey 换 accessToken
  Future<String> accessToken({bool force = false}) async {
    if (!force && _tokenFresh) return _token!;
    final String? ss = ssKeyFrom(cookie);
    if (ss == null || ss.isEmpty) {
      throw const AuthExpiredException(hint: 'Cookie 里没有 COOKIE_LOGIN_USER，重新粘一次');
    }
    final Response<dynamic> r = await _dio.get<dynamic>(
      '$apiBase/api/open/oauth2/getAccessTokenBySsKey',
      queryParameters: <String, String>{'clientId': clientId, 'ssKey': ss},
    );
    final Map<String, Object?> body = _asMap(r.data);
    final String t = '${body['accessToken'] ?? ''}';
    if (t.isEmpty) {
      final String res = '${body['res_message'] ?? body['errorMsg'] ?? ''}';
      if (res.contains('登录') || res.contains('token')) {
        throw const AuthExpiredException(hint: '天翼说登录失效了，重新粘一次 Cookie');
      }
      throw ParseException(res.isEmpty ? '天翼没给 accessToken' : res);
    }
    _token = t;
    _tokenAt = DateTime.now();
    final int expiresIn = _int(body['expiresIn']);
    if (expiresIn > 0) _tokenLife = Duration(seconds: expiresIn);
    return t;
  }

  @override
  Future<bool> verify() async {
    await accessToken(force: true);
    return true;
  }

  /// 14 §5.2：分享目录
  Future<List<RemoteEntry>> listShareDir({
    required String shareId,
    String accessCode = '',
    String? fileId,
    int pageNum = 1,
    int pageSize = 60,
  }) async {
    final String t = await accessToken();
    final Response<dynamic> r = await _dio.get<dynamic>(
      '$apiBase/api/open/share/listShareDir.action',
      queryParameters: <String, String>{
        'shareId': shareId,
        if (accessCode.isNotEmpty) 'accessCode': accessCode,
        'pageNum': '$pageNum',
        'pageSize': '$pageSize',
        'fileId': fileId ?? '',
        'isFolder': 'true',
        'accessToken': t,
      },
    );
    final Map<String, Object?> body = _asMap(r.data);
    if (body.isEmpty) throw const ParseException('天翼分享目录返回空');
    final Map<String, Object?> ao = _asMap(body['fileListAO']);
    final List<RemoteEntry> out = <RemoteEntry>[];
    for (final Object? raw in _asList(ao['folderList'])) {
      final Map<String, Object?> m = _asMap(raw);
      out.add(RemoteEntry(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        isDir: true,
      ));
    }
    for (final Object? raw in _asList(ao['fileList'])) {
      final Map<String, Object?> m = _asMap(raw);
      out.add(RemoteEntry(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        isDir: false,
        size: _int(m['size']),
      ));
    }
    return out;
  }

  /// 14 §5.3：分享直链
  Future<String> shareDownloadUrl({
    required String shareId,
    required String fileId,
    String accessCode = '',
  }) async {
    final String t = await accessToken();
    final Response<dynamic> r = await _dio.get<dynamic>(
      '$apiBase/api/open/share/getFileDownloadUrl.action',
      queryParameters: <String, String>{
        'shareId': shareId,
        'fileId': fileId,
        if (accessCode.isNotEmpty) 'accessCode': accessCode,
        'accessToken': t,
      },
    );
    final Map<String, Object?> body = _asMap(r.data);
    final String url = '${body['downloadUrl'] ?? ''}';
    if (url.isEmpty) throw const ResolveException(hint: '天翼没给直链');
    return url;
  }

  /// 14 §5.5：自己文件的直链
  Future<String> fileDownloadUrl(String fileId) async {
    final String t = await accessToken();
    final Response<dynamic> r = await _dio.get<dynamic>(
      '$apiBase/api/open/file/getFileDownloadUrl.action',
      queryParameters: <String, String>{'fileId': fileId, 'accessToken': t},
    );
    final Map<String, Object?> body = _asMap(r.data);
    final String url = '${body['downloadUrl'] ?? ''}';
    if (url.isEmpty) throw const ResolveException(hint: '天翼没给直链');
    return url;
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final String shareId = account.extra['shareId'] ?? '';
    if (shareId.isEmpty) {
      throw const ResolveException(hint: '天翼账号还没绑定分享链接（等登录那一轮接上）');
    }
    final String fid = path.replaceAll('/', '').trim();
    return listShareDir(shareId: shareId, fileId: fid.isEmpty ? null : fid);
  }

  @override
  Future<ResolvedUrl> resolve(RemoteEntry entry) async {
    if (entry.isDir) throw const ResolveException(hint: '目录没法直接播，先点进去');
    final String shareId = account.extra['shareId'] ?? '';
    if (shareId.isEmpty) throw const ResolveException(hint: '天翼账号还没绑定分享链接');
    final String url = await shareDownloadUrl(shareId: shareId, fileId: entry.id);
    return ResolvedUrl(
      url: url,
      headers: <String, String>{
        'Cookie': cookie,
        'Referer': 'https://cloud.189.cn/',
        'User-Agent': kDesktopUa,
      },
      resolver: 'tianyi',
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
