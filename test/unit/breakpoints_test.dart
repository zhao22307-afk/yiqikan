import 'package:flutter_test/flutter_test.dart';

import 'package:yiqikan/core/layout/breakpoints.dart';

void main() {
  group('screenClassOf（Material 3 断点 600 / 840）', () {
    test('599 及以下都是 compact', () {
      expect(screenClassOf(320), ScreenClass.compact);
      expect(screenClassOf(599), ScreenClass.compact);
      expect(screenClassOf(599.9), ScreenClass.compact);
    });

    test('600 是 medium 的下界（含等于）', () {
      expect(screenClassOf(600), ScreenClass.medium);
    });

    test('839 仍是 medium', () {
      expect(screenClassOf(839), ScreenClass.medium);
    });

    test('840 进 expanded', () {
      expect(screenClassOf(840), ScreenClass.expanded);
      expect(screenClassOf(1280), ScreenClass.expanded);
    });
  });

  group('gridColumns', () {
    test('三档分别 2 / 3 / 4 列', () {
      expect(gridColumns(ScreenClass.compact), 2);
      expect(gridColumns(ScreenClass.medium), 3);
      expect(gridColumns(ScreenClass.expanded), 4);
    });
  });

  group('isWideLandscape（播放页右侧竖排的判据）', () {
    test('手机竖屏不是宽横屏', () {
      expect(isWideLandscape(411, 891), isFalse);
    });

    test('手机横屏（891x411）算宽横屏；宽度不足 600 不算', () {
      expect(isWideLandscape(891, 411), isTrue);
      expect(isWideLandscape(599, 400), isFalse);
    });

    test('平板横屏算', () {
      expect(isWideLandscape(1024, 768), isTrue);
    });
  });
}
