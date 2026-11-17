import 'dart:async';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// F6 观看统计（10 号 :144：时长 / 平台 / 周报）。
///
/// 数据源只有 `history` 表，字段够用的：`watchedSeconds`（只增的累计秒数）做时长，
/// `watchedAt` 做时间轴，`source_id`/`source_kind` 做「平台」维度。
/// 表里**没有**「播放次数」「设备」「房间号」这些列 —— 所以 F6 的四项里
/// 「时长 / 平台 / 周报」能做，「播放次数」只能用条数近似（见报告第五段）。
///
/// 全部计算都走 SQL 聚合（COUNT/SUM/GROUP BY/DISTINCT），不把 history 读进内存。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

/// 一条「最常看」的聚合行
class _TopRow {
  const _TopRow(this.name, this.count, this.seconds);

  final String name;
  final int count;
  final int seconds;
}

class _StatsPageState extends ConsumerState<StatsPage> {
  late final AppDatabase _db = ref.read(appDatabaseProvider);

  bool _loading = true;
  int _count = 0;
  int _totalSeconds = 0;
  int _firstAt = 0;
  int _weekSeconds = 0;
  int _prevWeekSeconds = 0;
  int _monthSeconds = 0;
  int _prevMonthSeconds = 0;
  int _streakDays = 0;
  List<_TopRow> _top = const <_TopRow>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 本地时区的「今天 00:00」，不是 UTC
  DateTime get _today {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _weekStart =>
      _today.subtract(Duration(days: _today.weekday - 1));

  DateTime get _monthStart => DateTime(_today.year, _today.month, 1);

  Future<void> _load() async {
    final int weekStart = _weekStart.millisecondsSinceEpoch;
    final int prevWeekStart =
        _weekStart.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final int monthStart = _monthStart.millisecondsSinceEpoch;
    final int prevMonthStart =
        DateTime(_monthStart.year, _monthStart.month - 1, 1)
            .millisecondsSinceEpoch;

    final QueryRow total = await _db.customSelect(
      'SELECT COUNT(*) AS n, COALESCE(SUM(watched_seconds), 0) AS s, '
      'COALESCE(MIN(watched_at), 0) AS f FROM history',
    ).getSingle();

    final int week = await _sumBetween(weekStart, null);
    final int prevWeek = await _sumBetween(prevWeekStart, weekStart);
    final int month = await _sumBetween(monthStart, null);
    final int prevMonth = await _sumBetween(prevMonthStart, monthStart);

    final List<QueryRow> topRows = await _db.customSelect(
      // 源名字：有 source_id 就用它，没填的按 source_kind 翻成中文（表的 sourceKind 是
      // direct/bilibili/quark/emby/webdav/alist/maccms/room/dlna/download/local 这一套）
      'SELECT CASE WHEN source_id IS NOT NULL AND source_id != \'\' THEN source_id '
      "WHEN source_kind = 'room' THEN '房间' "
      "WHEN source_kind = 'direct' THEN '直链' "
      "WHEN source_kind = 'dlna' THEN '投屏' "
      "WHEN source_kind = 'download' THEN '下载' "
      "WHEN source_kind = 'local' THEN '本机' "
      "WHEN source_kind = 'web' THEN '网页' "
      'ELSE source_kind END AS sid, '
      'COUNT(*) AS n, COALESCE(SUM(watched_seconds), 0) AS s '
      'FROM history GROUP BY sid ORDER BY s DESC, n DESC LIMIT 3',
    ).get();

    final int streak = await _streak();

    if (!mounted) return;
    setState(() {
      _count = total.read<int>('n');
      _totalSeconds = total.read<int>('s');
      _firstAt = total.read<int>('f');
      _weekSeconds = week;
      _prevWeekSeconds = prevWeek;
      _monthSeconds = month;
      _prevMonthSeconds = prevMonth;
      _streakDays = streak;
      _top = topRows
          .map((QueryRow r) => _TopRow(
                r.read<String>('sid'),
                r.read<int>('n'),
                r.read<int>('s'),
              ))
          .toList(growable: false);
      _loading = false;
    });
    debugPrint('[YQK-STATS] n=$_count secs=$_totalSeconds week=$week '
        'prevWeek=$prevWeek month=$month prevMonth=$prevMonth '
        'streak=$streak top=${_top.map((_TopRow t) => '${t.name}:${t.count}').join(',')}');
  }

  /// SQL 里 SUM 一段区间；`toMs == null` 表示到今天为止
  Future<int> _sumBetween(int fromMs, int? toMs) async {
    final String sql = toMs == null
        ? 'SELECT COALESCE(SUM(watched_seconds), 0) AS s FROM history '
            'WHERE watched_at >= ?'
        : 'SELECT COALESCE(SUM(watched_seconds), 0) AS s FROM history '
            'WHERE watched_at >= ? AND watched_at < ?';
    final List<Variable<Object>> vars = toMs == null
        ? <Variable<Object>>[Variable.withInt(fromMs)]
        : <Variable<Object>>[
            Variable.withInt(fromMs),
            Variable.withInt(toMs),
        ];
    final QueryRow r = await _db.customSelect(sql, variables: vars).getSingle();
    return r.read<int>('s');
  }

  /// 连续观看天数：SQL 里只取「去重后的天序」，Dart 里数连续段。
  /// 天序 = (watchedAt + 本地偏移) / 一天，避免 UTC 跨天算错。
  Future<int> _streak() async {
    final int off = DateTime.now().timeZoneOffset.inMilliseconds;
    final List<QueryRow> rows = await _db.customSelect(
      'SELECT DISTINCT CAST((watched_at + ?) / 86400000 AS INTEGER) AS d '
      'FROM history ORDER BY d DESC LIMIT 400',
      variables: <Variable<Object>>[Variable.withInt(off)],
    ).get();
    if (rows.isEmpty) return 0;
    final int todayIdx =
        (DateTime.now().millisecondsSinceEpoch + off) ~/ 86400000;
    int streak = 0;
    int expect = todayIdx;
    for (final QueryRow r in rows) {
      final int d = r.read<int>('d');
      if (d == expect) {
        streak++;
        expect--;
      } else if (d < expect) {
        break;
      }
    }
    return streak;
  }

  Future<void> _clearAll() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空统计'),
        content: const Text('会把观看历史清空，统计数字也跟着归零。'
            '收藏、稍后看、下载不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.historyDao.clearAll();
    debugPrint('[YQK-STATS] clear all');
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  static String _dur(int seconds) {
    if (seconds <= 0) return '—';
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h 小时 $m 分';
    if (m > 0) return '$m 分';
    return '$seconds 秒';
  }

  static String _date(int ms) {
    if (ms <= 0) return '—';
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// 「本周比上周多/少多少」的一句话
  static String _delta(int now, int prev) {
    if (now == 0 && prev == 0) return '—';
    if (prev == 0) return '上周没记录';
    final int d = now - prev;
    if (d == 0) return '和上周持平';
    final String sign = d > 0 ? '+' : '-';
    return '$sign${_dur(d.abs())}';
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpace.page, 0, AppSpace.page, AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.sm),
          ...children,
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label,
              style: TextStyle(color: AppColors.textSub, fontSize: 12)),
          Text(value,
              style: TextStyle(color: AppColors.text, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('观看统计')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              children: <Widget>[
                _card('总览', <Widget>[
                  if (_count == 0)
                    Text('暂无数据',
                        style: TextStyle(color: AppColors.textSub))
                  else ...<Widget>[
                    _line('总时长', _dur(_totalSeconds)),
                    _line('总条数', '$_count 条'),
                    _line('最早一条', _date(_firstAt)),
                  ],
                ]),
                _card('本周 / 本月', <Widget>[
                  if (_count == 0)
                    Text('暂无数据',
                        style: TextStyle(color: AppColors.textSub))
                  else ...<Widget>[
                    _line('本周', '${_dur(_weekSeconds)}（${_delta(_weekSeconds, _prevWeekSeconds)}）'),
                    _line('上周', _dur(_prevWeekSeconds)),
                    _line('本月', '${_dur(_monthSeconds)}（${_delta(_monthSeconds, _prevMonthSeconds)}）'),
                    _line('上月', _dur(_prevMonthSeconds)),
                  ],
                ]),
                _card('最常看', <Widget>[
                  if (_count == 0 || _top.isEmpty)
                    Text('暂无数据',
                        style: TextStyle(color: AppColors.textSub))
                  else for (int i = 0; i < _top.length; i++)
                    _line('${i + 1}. ${_top[i].name}',
                        '${_top[i].count} 条 · ${_dur(_top[i].seconds)}'),
                ]),
                _card('连续观看', <Widget>[
                  if (_count == 0)
                    Text('暂无数据',
                        style: TextStyle(color: AppColors.textSub))
                  else ...<Widget>[
                    _line('今天算起连续', '$_streakDays 天'),
                    _line('日历', '本地时区，周一/1 号 00:00 分界'),
                  ],
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.page, AppSpace.sm, AppSpace.page, AppSpace.lg),
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => unawaited(_clearAll()),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空统计'),
                  ),
                ),
              ],
            ),
    );
  }
}