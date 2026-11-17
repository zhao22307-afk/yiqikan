import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/features/player/danmaku_painter.dart';
import 'package:yiqikan/platform/room/room_client.dart';

void main() {
  group('弹幕点赞（M8）', () {
    test('长按命中：按矩形取 id，重叠时取最上层，空白返回 null', () {
      final List<({String id, Rect rect})> boxes = <({String id, Rect rect})>[
        (id: 'dm_a', rect: const Rect.fromLTWH(10, 40, 100, 22)),
        (id: 'dm_b', rect: const Rect.fromLTWH(50, 40, 100, 22)),
      ];
      // 只有 a 覆盖
      expect(DanmakuPainter.hitTestRects(boxes, const Offset(20, 50)), 'dm_a');
      // 两条重叠：后画的 b 在上层
      expect(DanmakuPainter.hitTestRects(boxes, const Offset(60, 50)), 'dm_b');
      // 空白处：不能误命中
      expect(DanmakuPainter.hitTestRects(boxes, const Offset(300, 50)), isNull);
      // 空表
      expect(
        DanmakuPainter.hitTestRects(const <({String id, Rect rect})>[],
            const Offset(20, 50)),
        isNull,
      );
    });

    test('乐观 +1 与服务端增量取 max 合并，不回跳也不双计', () {
      // 本地乐观 +1 之后是 1
      const Map<String, int> local = <String, int>{'dm_a': 1};

      // 服务端广播回同一条 n=1：max 后仍是 1（不能回跳成 0，也不能加成 2）
      final Map<String, int> same = mergeDanmakuLikes(
        local,
        <String, dynamic>{
          'items': <String, dynamic>{'dm_a': 1},
        },
        'danmaku-likes',
      );
      expect(same['dm_a'], 1);

      // 别人也点了一次 → 服务端 n=2，抬到 2
      final Map<String, int> two = mergeDanmakuLikes(
        same,
        <String, dynamic>{
          'items': <String, dynamic>{'dm_a': 2},
        },
        'danmaku-likes',
      );
      expect(two['dm_a'], 2);

      // 收到旧的 n=1 帧不回退
      expect(
        mergeDanmakuLikes(
          two,
          <String, dynamic>{
            'items': <String, dynamic>{'dm_a': 1},
          },
          'danmaku-likes',
        )['dm_a'],
        2,
      );

      // 别人的点赞转发帧（没有计数）只当通知：不改计数。
      // 服务端「先 danmaku-likes{items}、再 relay 本帧」，这里再 +1 会让
      // 所有非发送者永远多 1（实测：探针点一次，手机侧 n 变 n+1）。
      final Map<String, int> notified = mergeDanmakuLikes(
        two,
        <String, dynamic>{'id': 'dm_a'},
        'danmaku-like',
      );
      expect(notified['dm_a'], 2);
      expect(identical(notified, two), isTrue, reason: '没变化应返回入参本身');

      // 兼容 11 号 §8.2 单条形状 {"id":..,"n":..}
      expect(
        mergeDanmakuLikes(
          const <String, int>{},
          <String, dynamic>{'id': 'dm_b', 'n': 7},
          'danmaku-likes',
        )['dm_b'],
        7,
      );
    });

    test('hello 快照的 danmaku_likes 全量替换（重进房以服务端为准）', () {
      final Map<String, int> snap = parseDanmakuLikesSnapshot(
        <String, dynamic>{'dm_a': 3, 'dm_b': '5', 'dm_zero': 0, '': 9},
      );
      expect(snap, <String, int>{'dm_a': 3, 'dm_b': 5});
      // 非 Map（老房间没有这个字段）→ 空表，不是 null
      expect(parseDanmakuLikesSnapshot(null), isEmpty);
      expect(parseDanmakuLikesSnapshot('garbage'), isEmpty);
    });
  });
}
