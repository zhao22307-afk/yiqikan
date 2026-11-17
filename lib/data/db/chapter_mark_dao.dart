part of 'app_database.dart';

/// H4：手动标的片头/片尾（v6 表 chapter_marks）。
///
/// 一个片子只有一行；两个值都是「秒」，-1 = 未设。写入用
/// [put]，只覆盖传入的那一侧，另一侧保持原值（先标片头、再标片尾是很常见的顺序）。
class ChapterMarkDao {
  ChapterMarkDao(this._db);

  final AppDatabase _db;

  /// 读一行；没标过返回 null
  Future<ChapterMark?> get(String mediaId) {
    return (_db.select(_db.chapterMarks)
          ..where((ChapterMarks t) => t.mediaId.equals(mediaId)))
        .getSingleOrNull();
  }

  /// 写一侧或两侧；只传 introEnd 就把 outroStart 保留原值。
  Future<void> put(String mediaId, {double? introEnd, double? outroStart}) async {
    final ChapterMark? old = await get(mediaId);
    await _db.into(_db.chapterMarks).insertOnConflictUpdate(
          ChapterMarksCompanion.insert(
            mediaId: mediaId,
            introEnd: Value<double>(introEnd ?? old?.introEnd ?? -1),
            outroStart: Value<double>(outroStart ?? old?.outroStart ?? -1),
            updatedAt: DateTime.now(),
          ),
        );
  }

  /// 清掉这部片子的两个标记
  Future<void> clear(String mediaId) {
    return (_db.delete(_db.chapterMarks)
          ..where((ChapterMarks t) => t.mediaId.equals(mediaId)))
        .go();
  }
}
