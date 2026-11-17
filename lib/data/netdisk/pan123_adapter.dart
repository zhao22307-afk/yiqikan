/// 123 云盘（14 §4）：五域名轮换 + sign_in + file/list/new + download_info。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/resolver.dart';
import '../local/secure_store.dart';
import 'netdisk_adapter.dart';
import 'netdisk_http.dart';

class Pan123Adapter extends NetdiskAdapter {
  Pan123Adapter({
    required super.account,
    required this.token,
    required this.store,
    Dio? dio,
    List<String>? domains,
  })  : _dio = dio ??
            newNetdiskDio(baseHeaders: <String, String>{
              'User-Agent': kDesktopUa,
              'platform': 'web',
              'app-version': '3',
              'X-App-Version': '3',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            }),
        _domains = domains ?? defaultDomains;

  static const String credKey = 'cred_123_token';

  /// 14 §4.0：五个域名都要能轮换（主站挂了自动换下一个）
  static const List<String> defaultDomains = <String>[
    'https://www.123684.com',
    'https://www.123pan.com',
    'https://www.123912.com',
    'https://www.123685.com',
    'https://www.123pan.cn',
  ];

  static const String loginBase = 'https://login.123pan.com';

  final String token;
  final SecureStore store;
  final Dio _dio;
  final List<String> _domains;

  int _domainAt = 0;

  @override
  NetdiskKind get kind => NetdiskKind.pan123;

  String get _base => _domains[_domainAt % _domains.length];

  /// 请求失败就换下一个域名重试一次（14 §4.0 的策略）
  Future<Response<dynamic>> _postRotating(
    String path,
    Map<String, Object?> body, {
    String? base,
  }) async {
    Object? lastError;
    for (int i = 0; i < _domains.length; i++) {
      try {
        return await _dio.post<dynamic>(
          '${base ?? _base}$path',
          data: body,
        );
      } on Object catch (e) {
        lastError = e;
        _domainAt++;
      }
    }
    throw AppException('123 云盘的五个域名都连不上：$lastError');
  }

  @override
  Future<bool> verify() async {
    if (token.isEmpty) {
      throw const AuthExpiredException(hint: '123 云盘要先登录拿 token');
    }
    final Response<dynamic> r = await _postRotating(
      '/api/user/info',
      const <String, Object?>{},
    );
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code == 401 || code == 403 || code == 5113) {
      throw const AuthExpiredException();
    }
    if (code != 0 && code != 200) {
      throw AppException('123 云盘返回错误码 $code');
    }
    return true;
  }

  /// 14 §4.1：账号密码登录
  Future<({String token, String privateKey})> signIn({
    required String passport,
    required String password,
  }) async {
    final Response<dynamic> r = await _dio.post<dynamic>(
      '$loginBase/api/user/sign_in',
      data: <String, Object?>{
        'passport': passport,
        'password': password,
        'remember': true,
      },
    );
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code != 0 && code != 200) {
      throw AppException(code == 4011 ? '账号或密码不对' : '123 云盘登录失败（$code）');
    }
    final Map<String, Object?> data = _asMap(body['data']);
    final String t = '${data['token'] ?? ''}';
    if (t.isEmpty) throw const ParseException('123 云盘登录没返回 token');
    return (token: t, privateKey: '${data['privateKey'] ?? ''}');
  }

  /// 14 §4.3：文件列表
  Future<List<RemoteEntry>> listNew({
    int parentFileId = 0,
    int limit = 100,
    int next = 0,
  }) async {
    final Response<dynamic> r = await _postRotating('/api/file/list/new', <String, Object?>{
      'driveId': 0,
      'limit': limit,
      'next': next,
      'orderBy': 'file_name',
      'orderDirection': 'asc',
      'parentFileId': parentFileId,
      'trashed': false,
      'SearchData': '',
      'Page': 1,
      'OnlyLookAbnormalFile': 0,
      'event': 'homeListFile',
      'operateType': 4,
      'inDirectSpace': false,
    });
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code == 401 || code == 5113) throw const AuthExpiredException();
    if (code != 0) throw AppException('123 云盘列表失败（$code）');
    final Map<String, Object?> data = _asMap(body['data']);
    final List<Object?> rows = _asList(data['InfoList']);
    return rows.map((Object? raw) {
      final Map<String, Object?> m = _asMap(raw);
      return RemoteEntry(
        id: '${m['FileId'] ?? ''}',
        name: '${m['FileName'] ?? ''}',
        isDir: _int(m['Type']) == 1,
        size: _int(m['Size']),
        extra: <String, String>{
          if (m['Etag'] != null) 'etag': '${m['Etag']}',
          if (m['S3KeyFlag'] != null) 's3keyFlag': '${m['S3KeyFlag']}',
          if (m['Type'] != null) 'type': '${m['Type']}',
        },
      );
    }).toList();
  }

  /// 14 §4.4：拿直链（注意参数是大写开头，和别处不一样；s3keyFlag 从列表里带过来）
  Future<String> downloadInfo(RemoteEntry entry) async {
    final Response<dynamic> r =
        await _postRotating('/api/file/download_info', <String, Object?>{
      'driveId': 0,
      'etag': entry.extra['etag'] ?? '',
      'fileId': _int(entry.id),
      's3keyFlag': entry.extra['s3keyFlag'] ?? '',
      'type': _int(entry.extra['type']),
      'fileName': entry.name,
      'size': entry.size,
    });
    final Map<String, Object?> body = _asMap(r.data);
    final int code = _int(body['code']);
    if (code == 401 || code == 5113) throw const AuthExpiredException();
    if (code != 0) throw AppException('123 云盘拿直链失败（$code）');
    final Map<String, Object?> data = _asMap(body['data']);
    final String url = '${data['DownloadUrl'] ?? ''}';
    if (url.isEmpty) throw const ResolveException(hint: '123 云盘没给直链');
    return url;
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final int parent = int.tryParse(path.replaceAll('/', '').trim()) ?? 0;
    return listNew(parentFileId: parent);
  }

  @override
  Future<ResolvedUrl> resolve(RemoteEntry entry) async {
    if (entry.isDir) throw const ResolveException(hint: '目录没法直接播，先点进去');
    final String url = await downloadInfo(entry);
    return ResolvedUrl(
      url: url,
      headers: <String, String>{'User-Agent': kDesktopUa},
      resolver: '123pan',
      lastUrlUpdate: DateTime.now(),
    );
  }

  @override
  Future<void> saveCredential() async => store.put(credKey, token);

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
