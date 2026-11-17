import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../db/app_database.dart';
import 'source_service.dart';
import 'tvbox_config.dart';

/// 把内置的 dianshi.json（assets/tvbox/dianshi.json）导进 sources 表。
///
/// 只导「本仓库能跑」的两类：csp（type=3 + csp_xxx，走内置 Java 侧）
/// 和 maccms（type=1 采集站）。js / py / other 只统计不导入 ——
/// 没有 JS/Python 引擎，导进来只会让用户点出一个假入口。
///
/// 幂等：按 (kind, apiUrl, ext) 判重，第二次跑 added=0。
class TvboxImporter {
  TvboxImporter({
    required this.service,
    Future<String> Function(String key)? loader,
  }) : _loader = loader ?? rootBundle.loadString;

  final SourceService service;
  final Future<String> Function(String key) _loader;

  static const String assetKey = 'assets/tvbox/dianshi.json';

  /// 返回新增条数；skip 只打日志（与任务书的 added/skip 对齐）。
  Future<int> importBuiltin({bool onlyUsable = true}) async {
    try {
      final String raw = await _loader(assetKey);
      return await importFrom(raw, onlyUsable: onlyUsable, label: 'builtin');
    } on Object catch (e) {
      debugPrint('[YQK-TVBOX] import builtin failed: $e');
      return 0;
    }
  }

  /// 从任意一份配置 JSON 导入（内置 asset、用户贴的 URL、用户粘的文本都走它）。
  ///
  /// [label] 只用于日志：`import <label> total=.. usable=.. added=.. skip=..`。
  Future<int> importFrom(
    String rawJson, {
    bool onlyUsable = true,
    String label = 'raw',
  }) async {
    int added = 0;
    int skip = 0;
    try {
      final List<TvboxSite> sites = TvboxConfig.parse(rawJson);
      final Map<String, int> stat = TvboxConfig.summarize(sites);
      final int usable = sites.where(TvboxConfig.usable).length;
      debugPrint('[YQK-TVBOX] config sites=${sites.length} csp=${stat['csp']} '
          'js=${stat['js']} py=${stat['py']} maccms=${stat['maccms']} '
          'other=${stat['other']}');

      final List<Source> existing = await service.dao.all(enabledOnly: false);
      final Set<String> keys = <String>{
        for (final Source s in existing)
          '${s.kind}|${s.apiUrl ?? ''}|${s.ext ?? ''}',
      };

      final int now = DateTime.now().millisecondsSinceEpoch;
      for (final TvboxSite site in sites) {
        if (onlyUsable && !TvboxConfig.usable(site)) continue;
        final String kind = TvboxConfig.classify(site) == 'maccms'
            ? SourceKind.maccms.name
            : SourceKind.tvbox.name;
        final String key = '$kind|${site.api}|${site.ext}';
        if (keys.contains(key)) {
          skip++;
          continue;
        }
        keys.add(key);
        await service.dao.upsert(Source(
          id: _idOf(site),
          name: site.name,
          kind: kind,
          apiUrl: site.api,
          ext: site.ext,
          enabled: 1,
          priority: 0,
          health: 'unknown',
          unreachable: 0,
          createdAt: now,
        ));
        added++;
      }
      debugPrint('[YQK-TVBOX] import $label total=${sites.length} '
          'usable=$usable added=$added skip=$skip');
    } on Object catch (e) {
      debugPrint('[YQK-TVBOX] import $label failed: $e');
    }
    return added;
  }

  /// 稳定 id：tvbox_<key>，便于重复导入时命中同一行。
  ///
  /// 注意：id 里保留中文与点号（SQLite TEXT 完全支持）。早先把非
  /// [A-Za-z0-9_-] 一律换成下划线，导致「配置中心 / 本地 / 预告」这类中文 key
  /// 全部塌成同一个 `tvbox______`，127 条 upsert 互相覆盖，库里只剩 14 行。
  static String _idOf(TvboxSite site) {
    final String raw = site.key.isEmpty ? site.api : site.key;
    final String safe = raw.replaceAll('|', '_');
    return 'tvbox_$safe';
  }
}
