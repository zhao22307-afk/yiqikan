import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 自建更新源的一条记录（G8）。
///
/// feed 是一个静态 JSON（放自己的对象存储 / 局域网 nginx 都行）：
/// ```json
/// { "version": "0.2.0", "url": "https://x/yqk-0.2.0.apk",
///   "sha256": "…64 hex…", "size": 51860417, "notes": "修了…" }
/// ```
/// 不连官方商店、不引 install_plugin：下载 → 校验 → 交给系统安装器。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.sha256,
    required this.size,
    this.notes = '',
  });

  final String version;
  final String url;
  final String sha256;
  final int size;
  final String notes;

  bool get hasHash => sha256.trim().length == 64;

  static UpdateInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String v = '${raw['version'] ?? ''}'.trim();
    final String u = '${raw['url'] ?? ''}'.trim();
    if (v.isEmpty || u.isEmpty) return null;
    return UpdateInfo(
      version: v,
      url: u,
      sha256: '${raw['sha256'] ?? ''}'.trim().toLowerCase(),
      size: raw['size'] is num ? (raw['size'] as num).toInt() : 0,
      notes: '${raw['notes'] ?? ''}'.trim(),
    );
  }

  static String sizeText(int bytes) {
    if (bytes <= 0) return '未知大小';
    final double mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  String toString() => 'UpdateInfo($version, $url, ${sizeText(size)})';
}

/// 语义版本比较：a<b 返回 -1，相等 0，a>b 返回 1。
///
/// 只认 `major.minor.patch`（多余段忽略，缺的段按 0 补），
/// 预发布后缀（`-beta.1`）直接丢掉 —— 我们不发预发布包。
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final String core = v.split('-').first.split('+').first.trim();
    final List<String> seg = core.split('.');
    final List<int> out = <int>[0, 0, 0];
    for (int i = 0; i < 3 && i < seg.length; i++) {
      out[i] = int.tryParse(seg[i].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }
    return out;
  }

  final List<int> pa = parts(a);
  final List<int> pb = parts(b);
  for (int i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

/// 只有「feed 的版本严格大于当前版本」才算有更新。
UpdateInfo? pickNewer(UpdateInfo? feed, String currentVersion) =>
    (feed != null && compareVersions(feed.version, currentVersion) > 0)
        ? feed
        : null;

/// 纯逻辑 + 一次 GET；网络/解析失败一律返回 null，绝不抛。
class UpdateChecker {
  UpdateChecker({Dio? dio, this.timeout = const Duration(seconds: 8)})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
              // 4xx/5xx 也要读 body：有些静态托管会带错误 JSON
              validateStatus: (int? _) => true,
            ));

  final Dio _dio;
  final Duration timeout;

  /// 拉 feed 并返回「比 currentVersion 新」的版本；没有更新/失败返回 null。
  Future<UpdateInfo?> check(String feedUrl, String currentVersion) async {
    final String url = feedUrl.trim();
    if (url.isEmpty) {
      debugPrint('[YQK-UPD] check skip: feed 为空');
      return null;
    }
    try {
      final Response<dynamic> res = await _dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode != 200) {
        debugPrint('[YQK-UPD] check fail http=${res.statusCode} url=$url');
        return null;
      }
      final Object? raw = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      final UpdateInfo? info = UpdateInfo.fromJson(raw);
      if (info == null) {
        debugPrint('[YQK-UPD] check fail: JSON 缺 version/url');
        return null;
      }
      final UpdateInfo? newer = pickNewer(info, currentVersion);
      debugPrint('[YQK-UPD] check feed=${info.version} current=$currentVersion '
          'newer=${newer != null}');
      return newer;
    } catch (e) {
      debugPrint('[YQK-UPD] check error $e');
      return null;
    }
  }

  /// 下载到 [destPath]，边写边算 SHA-256；不匹配就删文件并抛 [UpdateHashError]。
  Future<File> download(UpdateInfo info, String destPath,
      {ProgressCallback? onProgress}) async {
    final File out = File(destPath);
    await out.parent.create(recursive: true);
    if (await out.exists()) await out.delete();
    try {
      await _dio.download(
        info.url,
        destPath,
        onReceiveProgress: onProgress,
        deleteOnError: true,
      );
    } catch (e) {
      debugPrint('[YQK-UPD] download error $e');
      rethrow;
    }
    final int got = await out.length();
    final String digest = await sha256OfFile(out);
    debugPrint('[YQK-UPD] download done size=$got sha=$digest');
    if (info.hasHash && digest != info.sha256) {
      await out.delete();
      debugPrint('[YQK-UPD] hash mismatch expect=${info.sha256} got=$digest');
      throw UpdateHashError(info.sha256, digest);
    }
    if (info.size > 0 && got != info.size) {
      // 大小对不上但哈希（若给了）已经通过时只告警：CDN 压缩/分块边界会差几字节。
      debugPrint('[YQK-UPD] size mismatch expect=${info.size} got=$got');
    }
    return out;
  }

  static Future<String> sha256OfFile(File f) async {
    final Digest d = await sha256.bind(f.openRead()).first;
    return d.toString();
  }
}

class UpdateHashError implements Exception {
  UpdateHashError(this.expected, this.actual);
  final String expected;
  final String actual;

  @override
  String toString() =>
      'UpdateHashError(期望 $expected，实际 $actual，已删除下载文件)';
}
