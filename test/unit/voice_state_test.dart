import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/voice_client.dart';

/// 语音成员解析（M8 7a）。
///
/// 这一层的唯一职责：把服务端 `voice-state` 变成 UI 能直接画的东西。
/// 它不碰网络、不碰 WebRTC，所以能在单测里裸调 —— 这正是把它从 RoomClient
/// 里拆出来的原因。
void main() {
  group('parseVoiceState', () {
    test('全量解析：含 muted/speaking，joined 由 me 算出', () {
      final VoiceState s = parseVoiceState(<String, dynamic>{
        'type': 'voice-state',
        'room': '123456',
        'items': <dynamic>[
          <String, dynamic>{'id': 'm_a', 'name': '房主', 'muted': false, 'speaking': false},
          <String, dynamic>{'id': 'm_b', 'name': 'liker', 'muted': true, 'speaking': true},
        ],
      }, me: 'm_b');

      expect(s.items.length, 2);
      expect(s.ids, <String>{'m_a', 'm_b'});
      expect(s.joined, isTrue, reason: 'me 在 items 里就算已加入');
      expect(s.items[1].muted, isTrue);
      expect(s.items[1].speaking, isTrue);
      expect(s.length, 2);
      expect(s.has('m_a'), isTrue);
      expect(s.has(''), isFalse);
    });

    test('缺省字段兜住：没有 muted/speaking 就是 false，name 走 nickname', () {
      final VoiceState s = parseVoiceState(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'm_x', 'nickname': '老王'},
        ],
      });
      expect(s.items.single.name, '老王');
      expect(s.items.single.muted, isFalse);
      expect(s.items.single.speaking, isFalse);
      expect(s.joined, isFalse, reason: '没传 me 时不该判定已加入');
    });

    test('空 items / 非列表 / 缺 items 都不崩', () {
      expect(parseVoiceState(<String, dynamic>{'items': <dynamic>[]}).items, isEmpty);
      expect(parseVoiceState(<String, dynamic>{'items': null}).items, isEmpty);
      expect(parseVoiceState(<String, dynamic>{'items': 'oops'}).items, isEmpty);
      expect(parseVoiceState(<String, dynamic>{}).items, isEmpty);
      expect(VoiceState.empty.length, 0);
      expect(VoiceState.empty.joined, isFalse);
    });

    test('多余字段忽略、id 为空或非 Map 的条目被丢弃', () {
      final VoiceState s = parseVoiceState(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'm_a', 'name': 'A', 'extra': 1, 'level': 99},
          <String, dynamic>{'id': '', 'name': '无名'},
          <String, dynamic>{'name': '无 id'},
          'not-a-map',
        ],
      });
      expect(s.items.length, 1);
      expect(s.items.single.id, 'm_a');
    });
  });

  group('VoiceState.copyWith', () {
    test('full 标记可单独置位，items 与 joined 不动', () {
      final VoiceState base = parseVoiceState(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'm_a'},
        ],
      }, me: 'm_a');
      final VoiceState full = base.copyWith(full: true);
      expect(full.full, isTrue);
      expect(full.joined, isTrue);
      expect(full.items.length, 1);
      // 相等性按内容算：同样内容的两份状态 == 成立，ValueNotifier 才不会白刷
      expect(full, isNot(base));
      expect(base.copyWith(full: false), base);
    });
  });
}
