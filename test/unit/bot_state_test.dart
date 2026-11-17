import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/bot_state.dart';

void main() {
  group('parseBotState', () {
    test('合法帧：字段全读，aliases 吃 List', () {
      final BotState? s = parseBotState(<String, dynamic>{
        'type': 'bot-state',
        'enabled': true,
        'name': '小看',
        'aliases': <String>['小看', '小看酱'],
        'cooldownSec': 10,
        'hourlyQuota': 3,
        'occupySlot': true,
        'memberId': 'm_bot',
      });
      expect(s, isNotNull);
      expect(s!.enabled, isTrue);
      expect(s.name, '小看');
      expect(s.aliases, <String>['小看', '小看酱']);
      expect(s.cooldownSec, 10);
      expect(s.hourlyQuota, 3);
      expect(s.occupySlot, isTrue);
      expect(s.memberId, 'm_bot');
    });

    test('缺字段：全部走默认值，不抛；aliases 吃逗号串', () {
      final BotState? s = parseBotState(<String, dynamic>{
        'type': 'bot-state',
        'aliases': '小看, 小看酱',
      });
      expect(s, isNotNull);
      expect(s!.enabled, isTrue);
      expect(s.name, '小看');
      expect(s.aliases, <String>['小看', '小看酱']);
      expect(s.cooldownSec, 10);
      expect(s.hourlyQuota, 30);
      expect(s.reply, '我在');
      expect(s.memberId, '');
    });

    test('非 bot-state 帧返回 null；显式 false 才生效', () {
      expect(parseBotState(<String, dynamic>{'type': 'chat'}), isNull);
      final BotState? s = parseBotState(<String, dynamic>{
        'type': 'bot-state',
        'enabled': false,
        'occupySlot': false,
        'aliases': <String>[],
        'name': '阿看',
      });
      expect(s!.enabled, isFalse);
      expect(s.occupySlot, isFalse);
      expect(s.aliases, <String>['阿看']);
    });
  });
}
