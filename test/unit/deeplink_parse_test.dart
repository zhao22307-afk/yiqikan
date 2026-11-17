import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/deeplink/parse.dart';
import 'package:yiqikan/features/room/room_entry.dart';

/// 深链/二维码文本解析：三种入口靠同一份解析，错一个就进错房。
void main() {
  group('parseRoomLink', () {
    test('yiqikan://room/ABC123', () {
      final RoomLink? l = parseRoomLink('yiqikan://room/ABC123');
      expect(l, isNotNull);
      expect(l!.code, 'ABC123');
      expect(l.pwd, '');
    });

    test('yiqikan://room/ABC123?pwd=x 带密码', () {
      final RoomLink? l = parseRoomLink('yiqikan://room/ABC123?pwd=x');
      expect(l, isNotNull);
      expect(l!.code, 'ABC123');
      expect(l.pwd, 'x');
    });

    test('https://x/r/ABC123 分享短链', () {
      final RoomLink? l = parseRoomLink('https://x/r/ABC123');
      expect(l, isNotNull);
      expect(l!.code, 'ABC123');
      expect(l.pwd, '');
    });

    test('https://example.lan:8080/r/k3f9q2?pwd=123 小写码被规范化', () {
      final RoomLink? l =
          parseRoomLink('https://example.lan:8080/r/k3f9q2?pwd=123');
      expect(l, isNotNull);
      expect(l!.code, 'K3F9Q2');
      expect(l.pwd, '123');
    });

    test('垃圾串全部返回 null（静默丢弃）', () {
      const List<String> junk = <String>[
        '',
        '   ',
        '随便一句话',
        'https://x/abc',
        'https://x/r/',
        'yiqikan://play?url=file:///sdcard/a.mp4',
        'yiqikan://room/',
        'K3', // 太短
        'K3F9Q2K3F9Q2K3F9Q2', // 太长
        'not a link at all',
      ];
      for (final String s in junk) {
        expect(parseRoomLink(s), isNull, reason: '不该认成房间链接：$s');
      }
    });

    test('null 输入安全', () {
      expect(parseRoomLink(null), isNull);
      expect(parseScanText(null), isNull);
    });
  });

  group('parseScanText', () {
    test('二维码里就是一串房间码', () {
      final RoomLink? l = parseScanText('k3f9q2');
      expect(l, isNotNull);
      expect(l!.code, 'K3F9Q2');
    });

    test('二维码里是深链', () {
      final RoomLink? l = parseScanText(' yiqikan://room/ABC123?pwd=p ');
      expect(l, isNotNull);
      expect(l!.code, 'ABC123');
      expect(l.pwd, 'p');
    });

    test('二维码里是网址但不是进房码 → null', () {
      expect(parseScanText('https://example.com/watch?v=1'), isNull);
      expect(parseScanText('WIFI:S:home;T:WPA;P:12345678;;'), isNull);
      expect(parseScanText('一二三四五六'), isNull);
    });
  });

  group('JoinFrom 文案（11 号 §9.2）', () {
    test('三条入口各有各的失败文案', () {
      expect(JoinFrom.manual.failText, '房间码不对，或者房主没开');
      expect(JoinFrom.deeplink.failText, '这个链接打不开这个房间');
      expect(JoinFrom.scan.failText, '这个二维码不是进房码');
    });

    test('query 里的 from 认回枚举，认不出按手输', () {
      expect(joinFromOf('deeplink'), JoinFrom.deeplink);
      expect(joinFromOf('scan'), JoinFrom.scan);
      expect(joinFromOf('manual'), JoinFrom.manual);
      expect(joinFromOf(null), JoinFrom.manual);
      expect(joinFromOf('nonsense'), JoinFrom.manual);
      expect(JoinFrom.deeplink.tag, 'deeplink');
    });
  });
}
