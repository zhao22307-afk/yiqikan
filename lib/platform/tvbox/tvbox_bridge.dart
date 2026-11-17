import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';

/// TVBox 源（csp_xxx）的 Dart 侧入口。
///
/// 真正的类加载和调用在 Java 侧（`TvboxBatch.searchOne / detailOne / playOne`），
/// 通过 `yiqikan/probe` 通道走，调用方必须在异步上下文里用（Java 侧另起线程，
/// 但结果回来仍是主线程）。
class TvboxBridge {
  const TvboxBridge._();

  static const MethodChannel _ch = MethodChannel('yiqikan/probe');

  static Future<String> search({
    required String api,
    required String ext,
    required String kw,
  }) {
    return _call('tvboxSearch', <String>[api, ext, kw], tag: 'search api=$api kw=$kw');
  }

  static Future<String> detail({
    required String api,
    required String ext,
    required String id,
  }) {
    return _call('tvboxDetail', <String>[api, ext, id], tag: 'detail api=$api id=$id');
  }

  static Future<String> play({
    required String api,
    required String ext,
    required String flag,
    required String pid,
  }) {
    return _call('tvboxPlay', <String>[api, ext, flag, pid],
        tag: 'play api=$api flag=$flag pid=$pid');
  }

  static Future<String> _call(String method, List<String> args,
      {required String tag}) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final String? r = await _ch.invokeMethod<String>(method, args);
      sw.stop();
      debugPrint('[YQK-TVBOX] $tag n=${_countVodId(r ?? '')} ms=${sw.elapsedMilliseconds}');
      return r ?? '';
    } on PlatformException catch (e) {
      sw.stop();
      debugPrint('[YQK-TVBOX] $tag fail ${e.code} ms=${sw.elapsedMilliseconds}');
      throw AppException('TVBox 源调用失败：${e.message ?? e.code}');
    } on MissingPluginException catch (e) {
      sw.stop();
      debugPrint('[YQK-TVBOX] $tag no-channel ms=${sw.elapsedMilliseconds}');
      throw AppException('当前构建没有 TVBox 桥（$e）');
    }
  }

  /// 粗略数一下返回里有多少条 vod_id（日志用，不参与解析）。
  static int _countVodId(String text) {
    int n = 0, i = 0;
    while ((i = text.indexOf('vod_id', i)) >= 0) {
      n++;
      i += 6;
    }
    return n;
  }

  /// 把 Java 侧返回的 JSON 解析成 Map；返回 `{"error": ...}` 时原样给出。
  static Map<String, dynamic> decode(String text) {
    if (text.trim().isEmpty) return <String, dynamic>{};
    try {
      final Object? v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
      return <String, dynamic>{'raw': text};
    } on FormatException catch (e) {
      return <String, dynamic>{'error': '返回不是 JSON：$e'};
    }
  }
}
