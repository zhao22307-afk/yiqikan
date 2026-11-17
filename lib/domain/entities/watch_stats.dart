/// 观看统计（03 §4.2 `HistoryDao.stats` 的返回类型）。
///
/// 数据全部来自 `history` 表的 `watched_seconds` 增量累加结果，
/// 不是 `position` 之和 —— 用户"看到哪"会回退，统计不能跟着回退。
class WatchStats {
  const WatchStats({
    required this.totalSeconds,
    required this.totalItems,
    required this.bySource,
  });

  /// 累计观看秒数
  final int totalSeconds;

  /// 条目数
  final int totalItems;

  /// 按 sourceKind 分组的总秒数
  final Map<String, int> bySource;

  static const WatchStats empty = WatchStats(
    totalSeconds: 0,
    totalItems: 0,
    bySource: <String, int>{},
  );

  /// 累计观看时长（便于 UI 直接显示）
  Duration get totalDuration => Duration(seconds: totalSeconds);

  @override
  String toString() =>
      'WatchStats(totalSeconds: $totalSeconds, totalItems: $totalItems, bySource: $bySource)';
}
