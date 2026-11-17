import 'package:flutter/material.dart';

import 'app_colors.dart';

export 'app_colors.dart';

/// 主题：浅色（蓝白，05 §1）/ 深色（底 #0B0E14）。
///
/// 两套都从 [AppPalette] 常量生成，所以同一时刻可以并存；
/// 页面里的 `AppColors.xxx` 是 getter，跟着 [ThemeController] 走。
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppPalette.light, Brightness.light);

  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
    ).copyWith(
      primary: p.primary,
      onPrimary: p.textOn,
      primaryContainer: p.primarySoft,
      onPrimaryContainer: p.primary,
      secondary: p.accent,
      onSecondary: p.textOn,
      secondaryContainer: p.primarySoft,
      onSecondaryContainer: p.accent,
      error: p.danger,
      onError: p.textOn,
      surface: p.surface,
      onSurface: p.text,
      outline: p.stroke,
      outlineVariant: p.divider,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.section,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: AppText.title,
        titleMedium: AppText.section,
        titleSmall: AppText.card,
        bodyMedium: AppText.body,
        bodySmall: AppText.sub,
        labelSmall: AppText.label,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.textOn,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.btn),
          ),
          textStyle: AppText.card,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.strokeOn, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}
