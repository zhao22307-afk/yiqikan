import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/local/secure_store.dart';
import 'package:yiqikan/data/netdisk/emby_adapter.dart';

Map<String, dynamic> _fix(String name) =>
    (jsonDecode(File('test/fixtures/$name').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Emby 解析', () {
    test('AuthenticateByName → userId / token / serverId', () {
      final EmbyAuth a = EmbyParser.parseAuth(_fix('emby_auth.json'));
      expect(a.userId, '8f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f');
      expect(a.accessToken, 'tok_abcdef0123456789');
      expect(a.serverId, 'srv_1');
      expect(a.userName, 'demo');
    });

    test('缺少 AccessToken 抛 ParseException', () {
      expect(
        () => EmbyParser.parseAuth(<String, dynamic>{
          'User': <String, dynamic>{'Id': 'x'},
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('Items → 片单：目录在前、RunTimeTicks 换秒、进度换秒', () {
      final List<dynamic> rows = EmbyParser.parseItems(_fix('emby_items.json'));
      expect(rows.length, 3);
      expect(rows.first.name, '示例剧集');
      expect(rows.first.isDir, isTrue);
      final dynamic movie = rows.firstWhere((dynamic e) => '${e.name}' == '示例电影');
      expect(movie.isDir, isFalse);
      expect(movie.extra['duration'], '7200');
      expect(movie.extra['year'], '2020');
      final dynamic ep = rows.firstWhere((dynamic e) => '${e.name}' == '第 1 集');
      expect(ep.extra['duration'], '1500');
      expect(ep.extra['position'], '35');
    });
  });

  group('Emby DeviceId 持久化', () {
    test('同一个 store 两次 ensure 得到同一个 id，且落盘可复用', () async {
      final SecureStore store = SecureStore();
      await store.delete(EmbyDevice.storageKey);
      final EmbyDevice d1 = EmbyDevice(store);
      final String id1 = await d1.ensure();
      expect(id1.length, 36, reason: 'UUIDv4 形态');
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(id1), isTrue);

      // 新建一个实例（模拟重启 App / 重新登录）→ 必须复用同一个
      final EmbyDevice d2 = EmbyDevice(store);
      final String id2 = await d2.ensure();
      expect(id2, id1, reason: 'DeviceId 不能每次登录都变');

      // ignore: avoid_print
      print('[YQK-EMBY] deviceId=${id1.substring(0, 8)}… reuse=${id1 == id2}');
    });
  });
}
