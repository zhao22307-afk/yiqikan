/// 时长格式化：进度条两侧的 03:45 / 01:02:03。
///
/// 只做纯函数，方便单测；播放页不自己写 `toString()` 拼接。
String formatDuration(Duration d, {bool alwaysHours = false}) {
  final Duration v = d.isNegative ? Duration.zero : d;
  final int h = v.inHours;
  final int m = v.inMinutes.remainder(60);
  final int s = v.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0 || alwaysHours) {
    return '${two(h)}:${two(m)}:${two(s)}';
  }
  return '${two(m)}:${two(s)}';
}

/// 倍速显示：1 → 1.0x，1.25 → 1.25x
String formatRate(double rate) {
  final String text = rate == rate.roundToDouble()
      ? rate.toStringAsFixed(1)
      : rate.toString();
  return '${text}x';
}
