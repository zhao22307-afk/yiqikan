import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/lan_discovery.dart';

List<int> _pkt(Map<String, Object?> m) => utf8.encode(jsonEncode(m));

void main() {
  group('D25 附近房间包解析', () {
    test('合法包：六个字段都取出来', () {
      final LanRoom? r = parseLanPacket(
        _pkt(<String, Object?>{
          'v': 1,
          'code': '777777',
          'name': '测试房',
          'host': '小明',
          'port': 8080,
          'ts': 1794223364812,
        }),
        now: DateTime(2026, 11, 9, 20, 0, 0),
      );
      expect(r, isNotNull);
      expect(r!.code, '777777');
      expect(r.name, '测试房');
      expect(r.host, '小明');
      expect(r.port, 8080);
      expect(r.seenAt, DateTime(2026, 11, 9, 20, 0, 0));
    });

    test('坏包：非 JSON / 非 v1 / 空 code 都返回 null', () {
      expect(parseLanPacket(utf8.encode('{not json')), isNull);
      expect(
        parseLanPacket(_pkt(<String, Object?>{'v': 2, 'code': '777777'})),
        isNull,
      );
      expect(
        parseLanPacket(_pkt(<String, Object?>{'v': 1, 'code': ''})),
        isNull,
      );
    });

    test('自己的房间码不返回（selfCode 过滤）', () {
      final List<int> p = _pkt(<String, Object?>{
        'v': 1,
        'code': '464125',
        'name': '我的房',
        'host': '我',
        'port': 8080,
      });
      expect(parseLanPacket(p, selfCode: '464125'), isNull);
      expect(parseLanPacket(p, selfCode: '999999'), isNotNull);
    });
  });
}
