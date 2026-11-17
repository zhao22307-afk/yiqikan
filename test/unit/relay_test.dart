import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/relay.dart';

void main() {
  group('RelayStatus', () {
    test('未配置时 configured=false，不是「连不上」', () {
      const RelayStatus s = RelayStatus.unconfigured;
      expect(s.configured, isFalse);
      expect(s.connected, isFalse);
      expect(s.failed, isFalse); // 没配置不算故障
    });

    test('配了但连不上时 lastError 非空，failed 为真', () {
      final RelayStatus s = RelayStatus.fromJson(<String, Object?>{
        'success': true,
        'configured': true,
        'connected': false,
        'url': 'wss://relay.example.com/tunnel',
        'lastError': 'Connection refused',
        'attempts': 3,
      });
      expect(s.configured, isTrue);
      expect(s.connected, isFalse);
      expect(s.lastError, isNotEmpty);
      expect(s.failed, isTrue);
      expect(s.attempts, 3);
    });
  });

  group('RelayBackoff', () {
    test('最多 3 次退避，1s/2s/4s，之后返回 null 不再重连', () {
      final RelayBackoff b = RelayBackoff();
      expect(b.nextDelay(), 1000);
      expect(b.nextDelay(), 2000);
      expect(b.nextDelay(), 4000);
      expect(b.nextDelay(), isNull);
      expect(b.exhausted, isTrue);
      expect(b.attempts, RelayBackoff.maxAttempts);
    });

    test('reset 之后重新从 1s 开始', () {
      final RelayBackoff b = RelayBackoff();
      b.nextDelay();
      b.nextDelay();
      b.nextDelay();
      b.reset();
      expect(b.exhausted, isFalse);
      expect(b.nextDelay(), 1000);
    });
  });
}
