/// H4：片源自带的一条章节（只读，不写回文件）。
///
/// mpv 的 `chapter-list` 每项只有 `title` 和 `time`，没有结束时间：
/// 结束时间取「下一条的 start」，最后一条取总时长；总时长拿不到就传 -1
/// （语义 = 一直到片尾）。
class MediaChapter {
  const MediaChapter({
    required this.start,
    required this.end,
    this.title = '',
  });

  /// 起点（秒）
  final double start;

  /// 终点（秒）；-1 = 到片尾
  final double end;

  /// 章节名（mpv 里可能是空串）
  final String title;

  bool get hasEnd => end > start;

  /// 日志/面板都用同一个时间码格式：HH:MM:SS.mmm
  static String stamp(double seconds) {
    if (seconds < 0) return '--:--:--.---';
    final int ms = (seconds * 1000).round();
    final int h = ms ~/ 3600000;
    final int m = (ms % 3600000) ~/ 60000;
    final int s = (ms % 60000) ~/ 1000;
    final int r = ms % 1000;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}.${r.toString().padLeft(3, '0')}';
  }

  /// 面板里显示的短时间码：MM:SS
  static String short(double seconds) {
    if (seconds < 0) return '--:--';
    final int total = seconds.round();
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    final String mm = m.toString().padLeft(2, '0');
    final String ss = s.toString().padLeft(2, '0');
    return h > 0 ? '${h.toString()}:$mm:$ss' : '$mm:$ss';
  }

  @override
  String toString() =>
      '${stamp(start)}-${stamp(end)} ${title.isEmpty ? '(无标题)' : title}';
}
