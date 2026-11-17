import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/db/app_database.dart';
import '../../data/db/library_dao.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// F10 播放历史时间线：按天分组 + 本周统计（10 号 :135-151）。
///
/// 数据全来自 [LibraryDao.listHistory]（history 表），不自己算增量——
/// 增量与"看完清位置"的规则在 HistoryDao.record 里。
class HistoryTimeline extends StatefulWidget {
  const HistoryTimeline({
    super.key,
    required this.dao,
    this.onOpen,
  });

  final LibraryDao dao;

  /// 点一条 → 交给外面播（不在时间线里另写播放器）
  final void Function(History h)? onOpen;

  @override
  State<HistoryTimeline> createState() => _HistoryTimelineState();
}

class _HistoryTimelineState extends State<HistoryTimeline> {
  List<History> _rows = const <History>[];
  int _weekItems = 0;
  int _weekSeconds = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 本周 = 本周一 00:00 起
  static DateTime _weekStart(DateTime now) {
    final DateTime day = DateTime(now.year, now.month, now.day);
    return day.subtract(Duration(days: now.weekday - 1));
  }

  Future<void> _load() async {
    final List<History> rows = await widget.dao.listHistory(limit: 200);
    final WatchStatsLike stats = await _weekStats();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _weekItems = stats.items;
      _weekSeconds = stats.seconds;
      _loading = false;
    });
    debugPrint('[YQK-LIB] timeline n=${rows.length} '
        'weekItems=$_weekItems weekSeconds=$_weekSeconds');
  }

  Future<WatchStatsLike> _weekStats() async {
    final DateTime since = _weekStart(DateTime.now());
    final List<History> all =
        await widget.dao.db.select(widget.dao.db.historyTable).get();
    final int sinceMs = since.millisecondsSinceEpoch;
    final List<History> rows =
        all.where((History h) => h.watchedAt >= sinceMs).toList();
    int seconds = 0;
    for (final History h in rows) {
      seconds += h.watchedSeconds;
    }
    return WatchStatsLike(items: rows.length, seconds: seconds);
  }

  /// 今天 / 昨天 / M月d日
  static String _dayLabel(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime that = DateTime(d.year, d.month, d.day);
    final int diff = today.difference(that).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${d.month}月${d.day}日';
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _hours(int seconds) {
    if (seconds < 60) return '${seconds}秒';
    final int minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes分钟';
    return '${(minutes / 60).toStringAsFixed(1)}小时';
  }

  static String? _roomOf(History h) {
    final String? raw = h.extra;
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? v = jsonDecode(raw);
      if (v is Map<String, dynamic>) {
        final Object? room = v['room'];
        if (room is String && room.isNotEmpty) return room;
      }
    } catch (_) {
      // extra 是自由字段，解析不了就当没有房间号
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text('看过就会记在这儿',
            style: TextStyle(color: AppColors.textSub)),
      );
    }

    // 按天分组（列表已按 watchedAt desc 排好）
    final List<Widget> children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.page, AppSpace.md, AppSpace.page, AppSpace.sm),
        child: Text(
          '本周看了 $_weekItems 部 / 共 ${_hours(_weekSeconds)}',
          style: TextStyle(
              color: AppColors.textSub, fontSize: 13, letterSpacing: 0.4),
        ),
      ),
    ];
    String? lastDay;
    for (final History h in _rows) {
      final DateTime at = DateTime.fromMillisecondsSinceEpoch(h.watchedAt);
      final String label = _dayLabel(at);
      if (label != lastDay) {
        lastDay = label;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.page, AppSpace.md, AppSpace.page, AppSpace.xs),
          child: Text(label,
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ));
      }
      children.add(_HistoryRow(
        h: h,
        time: _hhmm(at),
        room: _roomOf(h),
        onTap: widget.onOpen == null ? null : () => widget.onOpen!(h),
      ));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xl),
        children: children,
      ),
    );
  }
}

class WatchStatsLike {
  const WatchStatsLike({required this.items, required this.seconds});

  final int items;
  final int seconds;
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.h,
    required this.time,
    this.room,
    this.onTap,
  });

  final History h;
  final String time;
  final String? room;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double dur = h.duration;
    final double ratio = dur <= 0 ? 0 : (h.position / dur).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.page, vertical: AppSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 44,
              child: Text(time,
                  style: TextStyle(
                      color: AppColors.textSub, fontSize: 12)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(h.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.text, fontSize: 14)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ratio.toDouble(),
                      minHeight: 3,
                      backgroundColor: AppColors.divider,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      if (dur > 0)
                        '${_fmt(h.position)} / ${_fmt(dur)}',
                      if (room != null) '房间 $room',
                    ].join(' · '),
                    style: TextStyle(
                        color: AppColors.textSub, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double seconds) {
    final int s = seconds.round();
    final int m = s ~/ 60;
    final int r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}