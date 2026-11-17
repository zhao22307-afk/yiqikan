import 'package:flutter/material.dart';

/// 主题色板：浅色（蓝白，05 §1 原值）/ 深色（#0B0E14 底，与启动图、图标一致）。
///
/// ⚠ 播放器那三层（videoBg/videoBar/videoText/videoDim）不参与主题切换：
/// 视频区永远是黑的，那是画布不是界面。
enum AppVariant { light, dark }

/// 用户可选的三档（跟系统 / 浅色 / 深色）——落 prefs 的是这个值。
enum ThemeModePref { system, light, dark }

/// G1 语言三档（跟系统 / 中文 / 英文）——落 prefs 的 'locale'。
enum LocalePref { system, zh, en }

/// 全局主题控制器。
///
/// [variant] 是**当前生效**的色板，由 [YiqikanApp] 每次 build 前算好（跟随时看
/// 系统亮度）；`AppColors` 的 getter 直接读它，所以页面代码不需要感知主题。
/// [revision] 只在用户改设置时 +1，用来触发根部重建。
class ThemeController {
  const ThemeController._();

  /// 当前生效色板。默认浅色（蓝白为默认，05 §1.1）。
  static AppVariant variant = AppVariant.light;

  /// 用户偏好（prefs 里的 theme_mode）。
  static ThemeModePref pref = ThemeModePref.system;

  /// 全局字号倍率（prefs 里的 font_scale），1.0 = 标准。
  static double fontScale = 1.0;

  /// 界面语言偏好（prefs 里的 locale）：跟系统 / 中文 / 英文。
  static LocalePref localePref = LocalePref.system;

  /// 设置变更时 +1，根部 ValueListenableBuilder 监听它重建整棵树。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void bump() => revision.value++;

  /// 由根部计算后写入，不触发通知（避免 build 期间 setState 循环）。
  static void applyEffective(AppVariant v) => variant = v;

  static void setPref(ThemeModePref p) {
    if (pref == p) return;
    pref = p;
    bump();
  }

  static void setFontScale(double s) {
    final double v = s.clamp(0.8, 1.6);
    if (fontScale == v) return;
    fontScale = v;
    bump();
  }

  static String prefName(ThemeModePref p) => switch (p) {
        ThemeModePref.system => 'system',
        ThemeModePref.light => 'light',
        ThemeModePref.dark => 'dark',
      };

  static void setLocalePref(LocalePref p) {
    if (localePref == p) return;
    localePref = p;
    bump();
  }

  /// 生效的 Locale：跟系统时返回 null（交给 Flutter 自己按系统语言选）。
  static Locale? get effectiveLocale => switch (localePref) {
        LocalePref.system => null,
        LocalePref.zh => const Locale('zh'),
        LocalePref.en => const Locale('en'),
      };

  static String localeName(LocalePref p) => switch (p) {
        LocalePref.system => 'system',
        LocalePref.zh => 'zh',
        LocalePref.en => 'en',
      };

  static LocalePref localeFromName(String? raw) => switch (raw) {
        'zh' => LocalePref.zh,
        'en' => LocalePref.en,
        _ => LocalePref.system,
      };

  static ThemeModePref prefFromName(String? raw) => switch (raw) {
        'light' => ThemeModePref.light,
        'dark' => ThemeModePref.dark,
        _ => ThemeModePref.system,
      };

  /// 字号三档（小 0.9 / 标准 1.0 / 大 1.15）；prefs 里存的是 double。
  static String fontScaleName(double s) {
    if (s < 0.95) return '小';
    if (s > 1.05) return '大';
    return '标准';
  }
}
