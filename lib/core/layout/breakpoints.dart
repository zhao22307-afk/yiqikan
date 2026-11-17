import 'package:flutter/foundation.dart';

/// G4 平板 / 折叠屏断点（Material 3 官方值：600 / 840）。
///
/// 只做**纯函数**：页面自己用 `LayoutBuilder` 拿 maxWidth 传进来，
/// 这样单测不需要 Widget 环境，也不受系统栏 / 键盘影响。
enum ScreenClass {
  /// 手机竖屏（< 600）
  compact,

  /// 小折叠展开 / 大屏手机横屏 / 小平板（600–840）
  medium,

  /// 平板 / 桌面（>= 840）
  expanded,
}

/// Material 3 的两个断点，改这里等于改全局。
const double kBreakpointMedium = 600;
const double kBreakpointExpanded = 840;

ScreenClass screenClassOf(double width) {
  if (width >= kBreakpointExpanded) return ScreenClass.expanded;
  if (width >= kBreakpointMedium) return ScreenClass.medium;
  return ScreenClass.compact;
}

/// 网格列数：手机 2 / 中屏 3 / 大屏 4。
int gridColumns(ScreenClass c) => switch (c) {
      ScreenClass.compact => 2,
      ScreenClass.medium => 3,
      ScreenClass.expanded => 4,
    };

/// 是否「横向大屏」——播放页要把浮层挪到右侧竖排。
///
/// 判据用布局给的尺寸（LayoutBuilder），不是 MediaQuery：后者含系统栏，
/// 横屏时状态栏高度会让判据抖动。
bool isWideLandscape(double width, double height) =>
    width >= kBreakpointMedium && width > height;

/// 一行日志，便于验收时在 logcat 里直接看到断点算出来的结果。
ScreenClass logScreenClass(String where, double width) {
  final ScreenClass c = screenClassOf(width);
  if (kDebugMode) {
    debugPrint('[YQK-UI] $where w=${width.toStringAsFixed(1)} '
        'class=${c.name} cols=${gridColumns(c)}');
  }
  return c;
}
