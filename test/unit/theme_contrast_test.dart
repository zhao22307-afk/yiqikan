import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/theme/theme_controller.dart';
import 'package:yiqikan/theme/app_colors.dart';

/// WCAG 相对亮度对比度（1..21）。
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('主题色板对比度（B-V5 白字白底的自动检查）', () {
    test('浅色：正文/次要/弱化文字与背景对比度都 >= 4.5', () {
      const AppPalette p = AppPalette.light;
      expect(_contrast(p.text, p.bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.text, p.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.textSub, p.bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.textSub, p.surface), greaterThanOrEqualTo(4.5));
      // textDim 只用于占位/提示（05 §1.1 原值就是弱对比），门槛按 2.0 卡。
      expect(_contrast(p.textDim, p.bg), greaterThanOrEqualTo(2.0));
    });

    test('深色：正文/次要文字与背景对比度都 >= 4.5', () {
      const AppPalette p = AppPalette.dark;
      expect(_contrast(p.text, p.bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.text, p.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.textSub, p.bg), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.textSub, p.surface), greaterThanOrEqualTo(4.5));
    });

    test('两套色板里正文色都不会等于背景色（防白字白底）', () {
      for (final AppPalette p in <AppPalette>[
        AppPalette.light,
        AppPalette.dark,
      ]) {
        expect(p.text, isNot(equals(p.bg)));
        expect(p.text, isNot(equals(p.surface)));
        expect(p.textSub, isNot(equals(p.bg)));
      }
    });

    test('AppColors 跟着 ThemeController.variant 走', () {
      ThemeController.applyEffective(AppVariant.light);
      expect(AppColors.bg, AppPalette.light.bg);
      ThemeController.applyEffective(AppVariant.dark);
      expect(AppColors.bg, AppPalette.dark.bg);
      // 播放器区不随主题
      expect(AppColors.videoBg, const Color(0xFF000000));
      ThemeController.applyEffective(AppVariant.light);
    });
  });

  group('字号倍率', () {
    test('三档命名', () {
      expect(ThemeController.fontScaleName(0.9), '小');
      expect(ThemeController.fontScaleName(1.0), '标准');
      expect(ThemeController.fontScaleName(1.15), '大');
    });

    test('setFontScale 有上下界且会触发 revision', () {
      final int before = ThemeController.revision.value;
      ThemeController.setFontScale(1.15);
      expect(ThemeController.fontScale, closeTo(1.15, 1e-9));
      expect(ThemeController.revision.value, greaterThan(before));
      ThemeController.setFontScale(9.0);
      expect(ThemeController.fontScale, lessThanOrEqualTo(1.6));
      ThemeController.setFontScale(1.0);
    });
  });
}
