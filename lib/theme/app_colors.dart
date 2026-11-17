import 'package:flutter/material.dart';

import '../core/theme/theme_controller.dart';

/// 一套色板（浅色 / 深色各一份，都是编译期常量）。
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.stroke,
    required this.strokeOn,
    required this.divider,
    required this.text,
    required this.textSub,
    required this.textDim,
    required this.textOn,
    required this.primary,
    required this.primaryEnd,
    required this.primarySoft,
    required this.accent,
    required this.success,
    required this.warn,
    required this.danger,
    required this.info,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color stroke;
  final Color strokeOn;
  final Color divider;
  final Color text;
  final Color textSub;
  final Color textDim;
  final Color textOn;
  final Color primary;
  final Color primaryEnd;
  final Color primarySoft;
  final Color accent;
  final Color success;
  final Color warn;
  final Color danger;
  final Color info;

  /// 蓝白（05 §1.1 原值）。
  static const AppPalette light = AppPalette(
    bg: Color(0xFFF5F8FE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7FAFF),
    surface3: Color(0xFFEFF4FE),
    stroke: Color(0xFFE4EAF4),
    strokeOn: Color(0xFF2563EB),
    divider: Color(0xFFEDF1F8),
    text: Color(0xFF0F1B2E),
    textSub: Color(0xFF5A6B85),
    textDim: Color(0xFF91A0B8),
    textOn: Color(0xFFFFFFFF),
    primary: Color(0xFF2563EB),
    primaryEnd: Color(0xFF5B8CFF),
    primarySoft: Color(0xFFEAF1FF),
    accent: Color(0xFF1D6FF2),
    success: Color(0xFF16A34A),
    warn: Color(0xFFF59E0B),
    danger: Color(0xFFE5484D),
    info: Color(0xFF1D6FF2),
  );

  /// 深色：底 #0B0E14（与启动图 / 图标同色），卡片逐级提亮。
  static const AppPalette dark = AppPalette(
    bg: Color(0xFF0B0E14),
    surface: Color(0xFF141922),
    surface2: Color(0xFF1A2130),
    surface3: Color(0xFF232B3A),
    stroke: Color(0xFF2A3342),
    strokeOn: Color(0xFF5B8CFF),
    divider: Color(0xFF222A36),
    text: Color(0xFFEAF0FA),
    textSub: Color(0xFF9FB0C6),
    textDim: Color(0xFF6B7C93),
    textOn: Color(0xFF0B0E14),
    primary: Color(0xFF5B8CFF),
    primaryEnd: Color(0xFF7FA6FF),
    primarySoft: Color(0xFF1B2436),
    accent: Color(0xFF7FA6FF),
    success: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF7FA6FF),
  );
}

/// 配色 / 尺寸 / 圆角 / 阴影令牌 —— 数值来自《05_UI规范.md》§1。
///
/// 规则：业务代码禁止写字面量颜色，一律走 AppColors。
///
/// 批 E11 起这些颜色是 **getter**，随 [ThemeController.variant] 在同
/// [AppPalette.light] / [AppPalette.dark] 之间切换；因此
/// `const TextStyle(... color: AppColors.xxx)` 这类写法必须去掉 `const`
/// （颜色不再是编译期常量）。
class AppColors {
  const AppColors._();

  static AppPalette get palette => ThemeController.variant == AppVariant.dark
      ? AppPalette.dark
      : AppPalette.light;

  // ---------- 背景与表面 ----------
  static Color get bg => palette.bg;
  static Color get surface => palette.surface;
  static Color get surface2 => palette.surface2;
  static Color get surface3 => palette.surface3;

  // ---------- 描边 / 分割 ----------
  static Color get stroke => palette.stroke;
  static Color get strokeOn => palette.strokeOn;
  static Color get divider => palette.divider;

  // ---------- 文字 ----------
  static Color get text => palette.text;
  static Color get textSub => palette.textSub;
  static Color get textDim => palette.textDim;

  /// 反白（主按钮上的字）。
  static Color get textOn => palette.textOn;

  // ---------- 品牌色 ----------
  static Color get primary => palette.primary;
  static Color get primaryEnd => palette.primaryEnd;
  static Color get primarySoft => palette.primarySoft;
  static Color get accent => palette.accent;

  // ---------- 语义色 ----------
  static Color get success => palette.success;
  static Color get warn => palette.warn;
  static Color get danger => palette.danger;
  static Color get info => palette.info;

  // ---------- 播放器（全屏视频层专用，永不随主题变）----------
  static const Color videoBg = Color(0xFF000000);
  static const Color videoBar = Color(0xB3000000);
  static const Color videoText = Color(0xFFFFFFFF);
  static const Color videoDim = Color(0xB3FFFFFF);

  /// 主色带透明度（渐变、遮罩、选中底）。
  static Color primaryA(double a) => primary.withValues(alpha: a);

  /// 任意色打薄成柔和底（默认 10%）。
  static Color soft(Color c, [double a = 0.10]) => c.withValues(alpha: a);
}

/// 间距令牌。
class AppSpace {
  const AppSpace._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 26;
  static const double xxl = 36;
  static const double page = 18;
}

/// 圆角令牌。
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double btn = 14;
  static const double pill = 999;
}

/// 阴影令牌。注意：禁止纯黑阴影（必须带蓝味 0x??102040）。
class AppShadow {
  const AppShadow._();

  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0A102040), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F102040), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> float = <BoxShadow>[
    BoxShadow(color: Color(0x14102040), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1A102040), blurRadius: 32, offset: Offset(0, 12)),
  ];

  static const List<BoxShadow> press = <BoxShadow>[
    BoxShadow(color: Color(0x08102040), blurRadius: 1, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> ring = <BoxShadow>[
    BoxShadow(color: Color(0x332563EB), blurRadius: 0, spreadRadius: 1.5),
  ];
}

/// 字号令牌（05 §1 字号表）。颜色同样随主题变，所以是 getter 不是 const。
class AppText {
  const AppText._();

  /// 大标题 25 / w700 / lh1.25 / ls-0.4
  static TextStyle get title => TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.4,
        color: AppColors.text,
      );

  /// 区块 17 / w600
  static TextStyle get section => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      );

  /// 卡片 15 / w600
  static TextStyle get card => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      );

  /// 正文 14 / w400 / lh1.6
  static TextStyle get body => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: AppColors.text,
      );

  /// 次要 12.5 / w400
  static TextStyle get sub => TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: AppColors.textSub,
      );

  /// 标签 11 / w600 / ls0.18
  static TextStyle get label => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.18,
        color: AppColors.textSub,
      );

  /// 数字 13 / w500
  static TextStyle get number => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.text,
      );
}
