part of '../app_database.dart';

/// 观看历史 DAO（03 §4.2）
///
/// 核心不变量：
///  * [History.position] 记录"看到哪"，允许回退；
///  * [History.watchedSeconds] 只增不减，增量为 `clamp(newPos - oldPos, 0, 60)`。
///  这样"拖回开头重看"不会把整片时长重复灌进统计。
@DriftAccessor(tables: <Type>[HistoryTable])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  /// 片尾 10 秒内算看完
  static const double _finishedTailSeconds = 10;

  /// 单次写入最多累计 60 秒，防止一次跳转被算成完整时长
  static const int _maxDeltaSeconds = 60;

  /// 记录/更新进度。
  ///
  /// 第一次写入按 0 秒起算（新条目只落 position，不凭首帧位置补计时）；
  /// 之后每次按位置差增量累加。
  Future<void> record({
    required String id,
    required String title,
    required String url,
    required String sourceKind,
    String? sourceId,
    String? poster,
    required double position,
    required double duration,
    int? episodeIndex,
    String? seriesId,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;

    await transaction(() async {
      final History? old = await (select(historyTable)
            ..where(($HistoryTableTable t) => t.id.equals(id)))
          .getSingleOrNull();

      int watched = old?.watchedSeconds ?? 0;
      if (old != null) {
        // 回退进度 delta 为 0，不会减；跳转超过 60 秒也只加 60
        final double rawDelta = position - old.position;
        final double delta =
            rawDelta.clamp(0, _maxDeltaSeconds.toDouble()).toDouble();
        watched += delta.round();
      }

      // 看完就清位置，下次从头播
      final bool finished =
          duration > 0 && position >= duration - _finishedTailSeconds;
      final double storedPosition = finished ? 0 : position;

      await into(historyTable).insertOnConflictUpdate(
        HistoryTableCompanion(
          id: Value<String>(id),
          title: Value<String>(title),
          url: Value<String>(url),
          sourceKind: Value<String>(sourceKind),
          sourceId: Value<String?>(sourceId),
          poster: Value<String?>(poster),
          position: Value<double>(storedPosition),
          duration: Value<double>(duration),
          watchedSeconds: Value<int>(watched),
          episodeIndex: Value<int?>(episodeIndex),
          seriesId: Value<String?>(seriesId),
          watchedAt: Value<int>(now),
          createdAt: Value<int>(old?.createdAt ?? now),
          extra: Value<String?>(old?.extra),
        ),
      );
    });
  }

  /// 最近观看
  Future<List<History>> recent({int limit = 50}) {
    return (select(historyTable)
          ..orderBy(<OrderClauseGenerator<$HistoryTableTable>>[
            ($HistoryTableTable t) =>
                OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  /// 继续观看：`5 < pos < dur - 10`
  Future<List<History>> continueWatching({int limit = 20}) {
    return (select(historyTable)
          ..where(($HistoryTableTable t) =>
              t.position.isBiggerThanValue(5) &
              t.position.isSmallerThan(t.duration - const Constant<double>(10)))
          ..orderBy(<OrderClauseGenerator<$HistoryTableTable>>[
            ($HistoryTableTable t) =>
                OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  Future<History?> byId(String id) {
    return (select(historyTable)..where(($HistoryTableTable t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 看完的条目。
  /// 注意：看完时 position 会被清成 0（见 [record]），所以判据是
  /// `duration > 0 && position = 0 && watched_seconds > 0`。
  Future<List<History>> completed() {
    return (select(historyTable)
          ..where(($HistoryTableTable t) =>
              t.duration.isBiggerThanValue(0) &
              t.position.isSmallerOrEqualValue(0) &
              t.watchedSeconds.isBiggerThanValue(0))
          ..orderBy(<OrderClauseGenerator<$HistoryTableTable>>[
            ($HistoryTableTable t) =>
                OrderingTerm(expression: t.watchedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<void> deleteById(String id) {
    return (delete(historyTable)
          ..where(($HistoryTableTable t) => t.id.equals(id)))
        .go();
  }

  Future<void> clearAll() => delete(historyTable).go();

  /// 统计：总时长（秒）、总条目、按源分组
  Future<WatchStats> stats({DateTime? since}) async {
    final List<History> rows = since == null
        ? await select(historyTable).get()
        : await (select(historyTable)..where(
                ($HistoryTableTable t) =>
                    t.watchedAt.isBiggerOrEqualValue(
                      since.millisecondsSinceEpoch,
                    )))
            .get();

    int totalSeconds = 0;
    final Map<String, int> bySource = <String, int>{};
    for (final History row in rows) {
      totalSeconds += row.watchedSeconds;
      bySource[row.sourceKind] =
          (bySource[row.sourceKind] ?? 0) + row.watchedSeconds;
    }
    return WatchStats(
      totalSeconds: totalSeconds,
      totalItems: rows.length,
      bySource: bySource,
    );
  }
}
