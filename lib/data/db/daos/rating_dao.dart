part of '../app_database.dart';

/// F9 片源评分（10 号 :147）：用户给每个源打 1–5 分，只存本地。
///
/// 表在 v4 migration 里 createTable 出来（只加表，不动旧表）。
/// 日志由调用方打（本 library 不 import flutter）。
class RatingDao {
  RatingDao(this._db);

  final AppDatabase _db;

  /// 打分（1..5 之外的分数按边界裁掉，不抛）
  Future<int> setScore(String sourceId, int score) async {
    final int s = score < 1 ? 1 : (score > 5 ? 5 : score);
    await _db.into(_db.sourceRatings).insertOnConflictUpdate(
          SourceRatingsCompanion.insert(
            sourceId: sourceId,
            score: s,
            ratedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return s;
  }

  Future<SourceRating?> byId(String sourceId) {
    return (_db.select(_db.sourceRatings)
          ..where((SourceRatings t) => t.sourceId.equals(sourceId)))
        .getSingleOrNull();
  }

  Future<List<SourceRating>> all() {
    return (_db.select(_db.sourceRatings)
          ..orderBy(<OrderClauseGenerator<$SourceRatingsTable>>[
            ($SourceRatingsTable t) => OrderingTerm.desc(t.ratedAt),
          ]))
        .get();
  }

  /// 平均分；一条都没有时返回 0（调用方据此决定不显示）
  Future<double> avg() async {
    final List<SourceRating> rows = await all();
    if (rows.isEmpty) return 0;
    int sum = 0;
    for (final SourceRating r in rows) {
      sum += r.score;
    }
    return sum / rows.length;
  }

  Future<void> remove(String sourceId) async {
    await (_db.delete(_db.sourceRatings)
          ..where((SourceRatings t) => t.sourceId.equals(sourceId)))
        .go();
  }
}
