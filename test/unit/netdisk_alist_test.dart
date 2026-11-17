import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/data/netdisk/alist_adapter.dart';

Map<String, dynamic> _fix(String name) =>
    (jsonDecode(File('test/fixtures/$name').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>);

void main() {
  group('AList fs/list', () {
    test('目录在前、中文名、sign 进 extra', () {
      final List<dynamic> rows = AlistParser.parseList(_fix('alist_fs_list.json'));
      expect(rows.length, 4);
      expect(rows[0].isDir, isTrue);
      expect(rows[1].isDir, isTrue);
      expect(rows[0].name, '电影');
      final dynamic mkv = rows.firstWhere((dynamic e) => '${e.name}' == '中文 片名.mkv');
      expect(mkv.extra['sign'], 'abc123');
      expect(mkv.size, 734003200);
      expect(mkv.sizeText, '700.0MB');
      final dynamic mp4 = rows.firstWhere((dynamic e) => '${e.name}' == 'a.mp4');
      expect(mp4.thumb, isNull);
    });

    test('code=401 抛 AuthExpiredException（不是返回空列表）', () {
      expect(
        () => AlistParser.parseList(<String, dynamic>{'code': 401, 'message': 'guest user is disabled'}),
        throwsA(isA<AuthExpiredException>()),
      );
    });

    test('code=500 抛 ResolveException', () {
      expect(
        () => AlistParser.parseList(<String, dynamic>{'code': 500, 'message': 'failed to list'}),
        throwsA(isA<ResolveException>()),
      );
    });

    test('data.content 为空数组返回空列表（真·空目录）', () {
      final List<dynamic> rows = AlistParser.parseList(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'content': <Object?>[], 'total': 0},
      });
      expect(rows, isEmpty);
    });
  });

  group('AList fs/get 两条路', () {
    test('raw_url 有值 → 走 raw，标记 viaRaw', () {
      final AlistResolved r = AlistParser.parseGet(_fix('alist_fs_get_raw.json'));
      expect(r.viaRaw, isTrue);
      expect(r.url, contains('cdn.example.com'));
      expect(r.provider, 'AliyundriveOpen');
    });

    test('raw_url 空但 url 有值 → 回落代理地址', () {
      final AlistResolved r = AlistParser.parseGet(_fix('alist_fs_get_proxy.json'));
      expect(r.viaRaw, isFalse);
      expect(r.url, 'https://alist.example.com/p/b.mp4');
    });

    test('两个都空 → ResolveException', () {
      expect(
        () => AlistParser.parseGet(_fix('alist_fs_get_empty.json')),
        throwsA(isA<ResolveException>()),
      );
    });
  });
}
