import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/entities/room_message.dart';
import 'package:yiqikan/features/player/danmaku_painter.dart';

RoomDanmaku dm(String id, double pos, {String text = '测试'}) => RoomDanmaku(
      id: id,
      from: 'm_1',
      name: '小明',
      text: text,
      pos: pos,
      at: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('轨道分配', () {
    test('空轨道就落到哈希给的那条，并记下右边缘', () {
      final List<double> lanes = List<double>.filled(
          DanmakuPainter.laneCount, double.negativeInfinity);
      final int lane = DanmakuPainter.allocateLane(
          id: 'dm_a', x: 300, width: 80, laneRight: lanes);
      expect(lane, inInclusiveRange(0, DanmakuPainter.laneCount - 1));
      expect(lanes[lane], 380);
    });

    test('同一轨道里离得太近就往下挪一轨', () {
      final List<double> lanes = List<double>.filled(
          DanmakuPainter.laneCount, double.negativeInfinity);
      final int first = DanmakuPainter.allocateLane(
          id: 'dm_same', x: 300, width: 80, laneRight: lanes);
      // 同一个 id 哈希相同，但这一条离得非常近 → 不许挤在同一轨
      final int second = DanmakuPainter.allocateLane(
          id: 'dm_same', x: 280, width: 80, laneRight: lanes);
      expect(second, isNot(first));
    });

    test('同轨已经有足够间隙就复用那一条', () {
      final List<double> lanes = List<double>.filled(
          DanmakuPainter.laneCount, double.negativeInfinity);
      final int first = DanmakuPainter.allocateLane(
          id: 'dm_gap', x: 300, width: 80, laneRight: lanes);
      // 右边缘 380，这一条从 500 开始，间隙 120 > laneGap(40)
      final int again = DanmakuPainter.allocateLane(
          id: 'dm_gap', x: 500, width: 80, laneRight: lanes);
      expect(again, first);
      expect(lanes[first], 580);
    });

    test('满轨也要给一条（返回合法下标，不越界）', () {
      final List<double> lanes = List<double>.filled(
          DanmakuPainter.laneCount, 1000);
      final int lane = DanmakuPainter.allocateLane(
          id: 'dm_full', x: 10, width: 80, laneRight: lanes);
      expect(lane, inInclusiveRange(0, DanmakuPainter.laneCount - 1));
    });
  });

  group('Paragraph 缓存', () {
    test('同样的 key 第二次命中，不重复排版', () {
      final DanmakuParagraphCache cache = DanmakuParagraphCache(capacity: 4);
      cache.get(
          text: '前方高能', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      cache.get(
          text: '前方高能', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      expect(cache.hits, 1);
      expect(cache.misses, 1);
      expect(cache.length, 1);
      expect(cache.hitRate, 0.5);
    });

    test('字号/颜色/加粗不同就是不同的 key', () {
      final DanmakuParagraphCache cache = DanmakuParagraphCache(capacity: 8);
      cache.get(text: 'a', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      cache.get(text: 'a', fontSize: 18, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      cache.get(text: 'a', fontSize: 15, color: 0xFF0000, bold: false,
          maxWidth: 432);
      cache.get(text: 'a', fontSize: 15, color: 0xFFFFFF, bold: true,
          maxWidth: 432);
      expect(cache.length, 4);
    });

    test('超过容量按 LRU 丢最久没用过的', () {
      final DanmakuParagraphCache cache = DanmakuParagraphCache(capacity: 3);
      cache.get(text: '1', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      cache.get(text: '2', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      cache.get(text: '3', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      // 重新使用 1，让它变成「最近用过」
      cache.get(text: '1', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      cache.get(text: '4', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      expect(cache.length, 3);
      // 2 是最久没用的，被淘汰 → 再取一次必然 miss
      final int before = cache.misses;
      cache.get(text: '2', fontSize: 15, color: 0xFFFFFF, bold: false,
          maxWidth: 432);
      expect(cache.misses, before + 1);
    });
  });

  group('shouldRepaint', () {
    DanmakuPainter painter(Duration pos, List<RoomDanmaku> items) =>
        DanmakuPainter(
          items: items,
          position: pos,
          safeTop: 20,
          safeBottom: 60,
        );

    test('位置变了要重绘，没变就不重绘', () {
      final DanmakuPainter a = painter(const Duration(seconds: 3), <RoomDanmaku>[dm('a', 1)]);
      final DanmakuPainter b = painter(const Duration(seconds: 3), <RoomDanmaku>[dm('a', 1)]);
      final DanmakuPainter c = painter(const Duration(seconds: 4), <RoomDanmaku>[dm('a', 1)]);
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });

    test('条数变了要重绘', () {
      final DanmakuPainter a = painter(const Duration(seconds: 3), <RoomDanmaku>[dm('a', 1)]);
      final DanmakuPainter b = painter(
          const Duration(seconds: 3), <RoomDanmaku>[dm('a', 1), dm('b', 2)]);
      expect(a.shouldRepaint(b), isTrue);
    });
  });

  group('字号倍数 clamp', () {
    test('对端误发字号 15 → 按 2.0 封顶，15px 字得到 30px', () {
      final double scale = DanmakuPainter.scaleFor(15);
      expect(scale, 2.0);
      expect(15 * scale, 30.0);
    });

    test('正常倍数 0.8 → 12px，不被 clamp 动', () {
      final double scale = DanmakuPainter.scaleFor(0.8);
      expect(scale, 0.8);
      expect(15 * scale, closeTo(12.0, 0.0001));
    });
  });

  group('时间窗口', () {
    test('窗口左边界 = 穿屏时间 + 1 秒（360 宽 / 120 速度 → 4 秒）', () {
      expect(DanmakuPainter.windowBehindFor(360, 120), 4.0);
      expect(DanmakuPainter.windowBehindFor(784, 120), closeTo(7.533, 0.001));
      expect(DanmakuPainter.windowBehindFor(0, 120), 8.0);
      expect(DanmakuPainter.windowBehindFor(360, 0), 8.0);
    });

    test('4 秒内画、4 秒外不画', () {
      expect(DanmakuPainter.inWindow(0, 4.0), isTrue);
      expect(DanmakuPainter.inWindow(0, 4.01), isFalse);
      expect(DanmakuPainter.inWindow(0, 3.99), isTrue);
    });

    test('未来 0.5 秒内的也画（提前进屏不闪）', () {
      expect(DanmakuPainter.inWindow(10.4, 10.0), isTrue);
      expect(DanmakuPainter.inWindow(10.6, 10.0), isFalse);
    });

    test('早于窗口的一律不画（pos=0 在 position=60）', () {
      expect(DanmakuPainter.inWindow(0, 60.0), isFalse);
      expect(DanmakuPainter.inWindow(55.9, 60.0), isFalse);
      expect(DanmakuPainter.inWindow(56.1, 60.0), isTrue);
    });
  });

  group('固定时间穿屏（04 §11.3）', () {
    test('超长文本按一屏宽排版：200 字在 432 宽下 w ≤ 432', () {
      final DanmakuParagraphCache cache = DanmakuParagraphCache();
      final String long = '长弹幕${'测' * 197}';
      final ui.Paragraph p = cache.get(
        text: long,
        fontSize: 15,
        color: 0xFFFFFFFF,
        bold: false,
        maxWidth: 432,
      );
      // 截断生效：宽度不超过排版上限，且明显超过一屏的 1/4（不是空段）
      expect(p.longestLine, lessThanOrEqualTo(432.0));
      expect(p.longestLine, greaterThan(400.0));
      // 同一句话在别的宽度上限下重新排版：全屏 784×1.2 = 940.8 → 放得更多
      final ui.Paragraph wide = cache.get(
        text: long,
        fontSize: 15,
        color: 0xFFFFFFFF,
        bold: false,
        maxWidth: 940.8,
      );
      expect(wide.longestLine, lessThanOrEqualTo(940.8));
      expect(wide.longestLine, greaterThan(p.longestLine),
          reason: '上限放宽后应该多显示几个字，说明宽度是跟着调用方自适应的');
    });

    test('短/中/长都 8 秒穿屏；三档速度是 8 秒的倍率', () {
      const double width = 360;
      // 8 秒时三条都刚好整条出左边界（x = -w），0 秒时都在右边缘
      for (final double w in <double>[90, 360, 440]) {
        expect(
            DanmakuPainter.xFor(
                width: width, elapsed: 0, textWidth: w, speed: 120),
            closeTo(width, 0.0001));
        expect(
            DanmakuPainter.xFor(
                width: width, elapsed: 8, textWidth: w, speed: 120),
            closeTo(-w, 0.0001));
        // 4 秒时正好走一半行程
        expect(
            DanmakuPainter.xFor(
                width: width, elapsed: 4, textWidth: w, speed: 120),
            closeTo((width - w) / 2, 0.0001));
      }
      // 档位语义：120 = 基准 8 秒；80 → 12 秒；180 → 5.33 秒
      expect(DanmakuPainter.crossSecondsFor(120), closeTo(8.0, 0.0001));
      expect(DanmakuPainter.crossSecondsFor(80), closeTo(12.0, 0.0001));
      expect(DanmakuPainter.crossSecondsFor(180), closeTo(5.3333, 0.0001));
      // 固定时间方案的特征：长弹幕的 px/s 比短弹幕快
      final double vShort = DanmakuPainter.travelSpeedFor(
          width: width, textWidth: 90, speed: 120);
      final double vLong = DanmakuPainter.travelSpeedFor(
          width: width, textWidth: 440, speed: 120);
      expect(vShort, closeTo(450 / 8, 0.0001));
      expect(vLong, closeTo(800 / 8, 0.0001));
      expect(vLong, greaterThan(vShort));
    });
  });
}
