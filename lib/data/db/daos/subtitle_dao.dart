part of '../app_database.dart';

/// F12 字幕库（10 号 :150）：本地文件 / 在线地址二选一，按片子归属。
///
/// 表在 v3 migration 里 createTable 出来（只加表，不动旧表）。
class SubtitleDao {
  SubtitleDao(this._db);

  final AppDatabase _db;

  /// 写一条（同 id 覆盖）；返回是否新增（false = 更新了已有记录）。
  /// 日志由调用方打（本 library 不依赖 flutter，见 app_database.dart 顶部 import）。
  Future<bool> upsert(SubtitlesCompanion r) async {
    final String id = r.id.value;
    final SubtitleRow? old = await byId(id);
    await _db.into(_db.subtitles).insertOnConflictUpdate(r);
    return old == null;
  }

  Future<SubtitleRow?> byId(String id) {
    return (_db.select(_db.subtitles)..where((Subtitles t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 某片子的全部字幕：最近用过的排前面，同分按加入时间倒序
  Future<List<SubtitleRow>> byMedia(String mediaUrl) {
    return (_db.select(_db.subtitles)
          ..where((Subtitles t) => t.mediaUrl.equals(mediaUrl))
          ..orderBy(<OrderClauseGenerator<$SubtitlesTable>>[
            ($SubtitlesTable t) => OrderingTerm.desc(t.lastUsedAt),
            ($SubtitlesTable t) => OrderingTerm.desc(t.addedAt),
          ]))
        .get();
  }

  Future<void> setLastUsed(String id) async {
    await (_db.update(_db.subtitles)..where((Subtitles t) => t.id.equals(id)))
        .write(SubtitlesCompanion(
      lastUsedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> remove(String id) async {
    await (_db.delete(_db.subtitles)..where((Subtitles t) => t.id.equals(id)))
        .go();
  }

  Future<int> countAll() async {
    final List<SubtitleRow> rows =
        await (_db.select(_db.subtitles)..limit(1 << 30)).get();
    return rows.length;
  }
}
