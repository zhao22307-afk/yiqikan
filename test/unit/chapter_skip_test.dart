import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/chapter_skip.dart';

void main() {
  group('ChapterSkip.decide', () {
    test('片头命中：pos 明显早于 introEnd 时返回 toIntroEnd', () {
      final ChapterSkip s = ChapterSkip();
      final SkipAction a = s.decide(
        pos: 3,
        duration: 1440,
        introEnd: 92.5,
        outroStart: -1,
        skipIntro: true,
        skipOutro: false,
      );
      expect(a, SkipAction.toIntroEnd);
      expect(s.introSkipped, isTrue);
    });

    test('已在目标附近不跳（tolerance 防抖）', () {
      final ChapterSkip s = ChapterSkip();
      // 91.5 距离 92.5 只有 1.0 < tolerance 1.5
      expect(
        s.decide(
          pos: 91.5,
          duration: 1440,
          introEnd: 92.5,
          outroStart: -1,
          skipIntro: true,
          skipOutro: false,
        ),
        SkipAction.none,
      );
      expect(s.introSkipped, isFalse);
    });

    test('skipIntro=false 不跳', () {
      final ChapterSkip s = ChapterSkip();
      expect(
        s.decide(
          pos: 1,
          duration: 1440,
          introEnd: 92.5,
          outroStart: -1,
          skipIntro: false,
          skipOutro: false,
        ),
        SkipAction.none,
      );
    });

    test('outroStart 命中返 none，只置 outroHit', () {
      final ChapterSkip s = ChapterSkip();
      final SkipAction a = s.decide(
        pos: 1380,
        duration: 1440,
        introEnd: -1,
        outroStart: 1380,
        skipIntro: false,
        skipOutro: true,
      );
      expect(a, SkipAction.none);
      expect(s.outroHit, isTrue);
    });

    test('-1 未设不跳', () {
      final ChapterSkip s = ChapterSkip();
      expect(
        s.decide(
          pos: 0.5,
          duration: 1440,
          introEnd: -1,
          outroStart: -1,
          skipIntro: true,
          skipOutro: true,
        ),
        SkipAction.none,
      );
      expect(s.outroHit, isFalse);
    });

    test('同一片只跳一次：拖回 10 秒不再跳', () {
      final ChapterSkip s = ChapterSkip();
      expect(
        s.decide(
          pos: 2,
          duration: 1440,
          introEnd: 92.5,
          outroStart: -1,
          skipIntro: true,
          skipOutro: false,
        ),
        SkipAction.toIntroEnd,
      );
      // 跳过之后用户又拖回 10 秒
      expect(
        s.decide(
          pos: 10,
          duration: 1440,
          introEnd: 92.5,
          outroStart: -1,
          skipIntro: true,
          skipOutro: false,
        ),
        SkipAction.none,
      );
      // 换片复位后又能跳
      s.reset();
      expect(s.introSkipped, isFalse);
      expect(
        s.decide(
          pos: 5,
          duration: 1440,
          introEnd: 92.5,
          outroStart: -1,
          skipIntro: true,
          skipOutro: false,
        ),
        SkipAction.toIntroEnd,
      );
    });
  });
}
