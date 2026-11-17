import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../data/db/app_database.dart';
import '../../data/local/prefs.dart';

/// 备份导入的「只补不覆盖」合并逻辑。
///
/// 单独拎出来是为了能直接拿内存库做单测：vivo 的文件选择器只能在它自己的
/// 「最近文件」索引里翻，应用私有目录里的导出文件它看不到，端到端导入在真机
/// 上不好复现，逻辑本身必须被单测覆盖（F7 验收 B-V3/B-V4）。
class BackupMerger {
  const BackupMerger._();

  /// 返回 `{'added': {...}, 'skipped': {...}}`，键为 src / fav / his / set。
  static Future<Map<String, Map<String, int>>> merge(
    AppDatabase db,
    Map<String, Object?> raw,
  ) async {
    final List<Object?> srcs =
        (raw['sources'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> favs =
        (raw['favorites'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> his =
        (raw['history'] as List<Object?>?) ?? const <Object?>[];
    final Map<String, Object?> settings =
        (raw['settings'] as Map<String, Object?>?) ?? const <String, Object?>{};

    final Map<String, int> added = <String, int>{'src': 0, 'fav': 0, 'his': 0, 'set': 0};
    final Map<String, int> skipped = <String, int>{'src': 0, 'fav': 0, 'his': 0, 'set': 0};

    // sources：按 apiUrl 去重（没有 apiUrl 用 id）
    final List<Source> oldSrc = await db.select(db.sources).get();
    final Set<String> srcKeys = <String>{
      for (final Source s in oldSrc) s.apiUrl ?? 'id:${s.id}',
    };
    for (final Object? o in srcs) {
      if (o is! Map<String, Object?>) continue;
      final String key = (o['apiUrl'] as String?) ?? 'id:${o['id']}';
      if (srcKeys.contains(key)) {
        skipped['src'] = skipped['src']! + 1;
        continue;
      }
      await db.into(db.sources).insert(SourcesCompanion.insert(
            id: (o['id'] as String?) ?? 'bk_${srcKeys.length}',
            name: (o['name'] as String?) ?? '导入的源',
            kind: (o['kind'] as String?) ?? 'direct',
            apiUrl: Value<String?>(o['apiUrl'] as String?),
            baseUrl: Value<String?>(o['baseUrl'] as String?),
            username: Value<String?>(o['username'] as String?),
            config: Value<String?>(o['config'] as String?),
            createdAt: (o['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          ));
      srcKeys.add(key);
      added['src'] = added['src']! + 1;
    }

    // favorites：按 id 去重
    final Set<String> favIds = <String>{
      for (final Favorite f in await db.select(db.favorites).get()) f.id,
    };
    for (final Object? o in favs) {
      if (o is! Map<String, Object?>) continue;
      final String id = (o['id'] as String?) ?? '';
      if (id.isEmpty || favIds.contains(id)) {
        skipped['fav'] = skipped['fav']! + 1;
        continue;
      }
      await db.into(db.favorites).insert(FavoritesCompanion.insert(
            id: id,
            title: (o['title'] as String?) ?? '',
            url: (o['url'] as String?) ?? '',
            sourceKind: (o['sourceKind'] as String?) ?? 'direct',
            sourceId: Value<String?>(o['sourceId'] as String?),
            poster: Value<String?>(o['poster'] as String?),
            tag: Value<String?>(o['tag'] as String?),
            note: Value<String?>(o['note'] as String?),
            addedAt: (o['addedAt'] as num?)?.toInt() ?? 0,
          ));
      favIds.add(id);
      added['fav'] = added['fav']! + 1;
    }

    // history：按 id 去重
    final Set<String> hisIds = <String>{
      for (final History h in await db.select(db.historyTable).get()) h.id,
    };
    for (final Object? o in his) {
      if (o is! Map<String, Object?>) continue;
      final String id = (o['id'] as String?) ?? '';
      if (id.isEmpty || hisIds.contains(id)) {
        skipped['his'] = skipped['his']! + 1;
        continue;
      }
      await db.into(db.historyTable).insert(HistoryTableCompanion.insert(
            id: id,
            title: (o['title'] as String?) ?? '',
            url: (o['url'] as String?) ?? '',
            sourceKind: (o['sourceKind'] as String?) ?? 'direct',
            sourceId: Value<String?>(o['sourceId'] as String?),
            poster: Value<String?>(o['poster'] as String?),
            position: Value<double>((o['position'] as num?)?.toDouble() ?? 0),
            duration: Value<double>((o['duration'] as num?)?.toDouble() ?? 0),
            watchedAt: (o['watchedAt'] as num?)?.toInt() ?? 0,
            createdAt: (o['createdAt'] as num?)?.toInt() ?? 0,
          ));
      hisIds.add(id);
      added['his'] = added['his']! + 1;
    }

    // settings：只补当前为空的项，不动用户已设置的
    final Prefs prefs = await Prefs.open();
    for (final MapEntry<String, Object?> e in settings.entries) {
      if (!PrefKeys.all.contains(e.key)) continue;
      if (prefs.getAny(e.key) != null) {
        skipped['set'] = skipped['set']! + 1;
        continue;
      }
      final Object? v = e.value;
      if (v is String) {
        await prefs.setString(e.key, v);
      } else if (v is int) {
        await prefs.setInt(e.key, v);
      } else if (v is double) {
        await prefs.setDouble(e.key, v);
      } else if (v is bool) {
        await prefs.setBool(e.key, v);
      } else {
        skipped['set'] = skipped['set']! + 1;
        continue;
      }
      added['set'] = added['set']! + 1;
    }

    debugPrint('[YQK-BACKUP] merge 新增 src=${added['src']} fav=${added['fav']} '
        'his=${added['his']} set=${added['set']} | '
        '跳过 src=${skipped['src']} fav=${skipped['fav']} his=${skipped['his']} '
        'set=${skipped['set']}');
    return <String, Map<String, int>>{'added': added, 'skipped': skipped};
  }
}
