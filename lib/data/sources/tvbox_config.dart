import 'dart:convert';

import 'package:flutter/foundation.dart';

/// dianshi.json（TVBox 配置）的极简解析器。
///
/// 只做两件事：把 `sites` 数组读成 [TvboxSite]，以及给每个 site 分个类
/// （csp / js / py / maccms / other）。不碰网络、不碰 Java 侧。
class TvboxSite {
  const TvboxSite({
    required this.key,
    required this.name,
    required this.api,
    required this.ext,
    required this.type,
  });

  final String key;
  final String name;

  /// 原始 api 字段：type=3 是 `csp_App99` 这种；type=1 是采集站接口地址
  final String api;

  /// type=3 源初始化用的 ext 原文（可能是空串、JSON、或普通字符串）
  final String ext;
  final int type;

  /// csp_ 前缀去掉后的类名（com.github.catvod.spider.<clsName>）；非 csp 源返回空串
  String get clsName => api.startsWith('csp_') ? api.substring(4) : '';

  String get kind => TvboxConfig.classify(this);

  @override
  String toString() => 'TvboxSite($key, api=$api, type=$type, ext=${ext.length})';
}

class TvboxConfig {
  const TvboxConfig._();

  /// 解析整份配置；坏数据跳过，不抛异常。
  static List<TvboxSite> parse(String json) {
    final List<TvboxSite> out = <TvboxSite>[];
    try {
      final Object? root = json.isEmpty ? null : jsonDecode(json);
      if (root is! Map) return out;
      final Object? sites = root['sites'];
      if (sites is! List) return out;
      for (final Object? e in sites) {
        if (e is! Map) continue;
        final String key = '${e['key'] ?? ''}';
        final String api = '${e['api'] ?? ''}';
        if (api.isEmpty) continue;
        out.add(TvboxSite(
          key: key,
          name: _text(e['name'], key),
          api: api,
          ext: _text(e['ext'], ''),
          type: int.tryParse('${e['type'] ?? 0}') ?? 0,
        ));
      }
    } on Object catch (e) {
      debugPrint('[YQK-TVBOX] config parse fail: $e');
    }
    return out;
  }

  /// 分类规则（与任务书一致，顺序不能换）
  static String classify(TvboxSite s) {
    if (s.type == 1) return 'maccms';
    if (s.type == 3 && s.api.startsWith('csp_')) return 'csp';
    if (s.type == 3 && s.api.contains('drpy')) return 'js';
    if (s.type == 3 && s.api.startsWith('./py/')) return 'py';
    return 'other';
  }

  /// 这个源能不能在本仓库用（csp 走内置 Java 侧，maccms 走采集站解析）
  static bool usable(TvboxSite s) {
    final String k = classify(s);
    return k == 'csp' || k == 'maccms';
  }

  /// 统计各类数量（报告与日志用）
  static Map<String, int> summarize(List<TvboxSite> sites) {
    final Map<String, int> m = <String, int>{
      'csp': 0,
      'js': 0,
      'py': 0,
      'maccms': 0,
      'other': 0,
    };
    for (final TvboxSite s in sites) {
      final String k = classify(s);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  static String _text(Object? v, String fallback) {
    if (v == null) return fallback;
    final String s = '$v';
    return s.isEmpty ? fallback : s;
  }
}
