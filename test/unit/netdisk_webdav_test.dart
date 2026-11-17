import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/core/utils/redact.dart';
import 'package:yiqikan/data/netdisk/webdav_adapter.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync(encoding: utf8);

void main() {
  group('WebDAV 207 解析', () {
    test('跳过目录自己、区分目录与文件、中文名与 + 号都对', () {
      final List<dynamic> rows = WebDavParser.parse(
        _fixture('webdav_207.xml'),
        requestPath: '/dav/',
      );
      final List<String> names = rows.map((dynamic e) => '${e.name}').toList();
      expect(names.contains('dav'), isFalse, reason: '第一条是目录自己，必须跳过');
      expect(names, contains('movies'));
      expect(names, contains('中文 片名.mp4'));
      expect(names, contains('readme.txt'));
      expect(names, contains('a+b.mp4'), reason: '%2B 不能变成空格');

      final dynamic dir = rows.firstWhere((dynamic e) => '${e.name}' == 'movies');
      expect(dir.isDir, isTrue, reason: '有 collection 才是目录');

      final dynamic f1 = rows.firstWhere((dynamic e) => '${e.name}' == '中文 片名.mp4');
      expect(f1.isDir, isFalse, reason: '空 resourcetype 是文件');
      expect(f1.size, 12345678);
      expect(f1.extra['content-type'], 'video/mp4');
      expect(f1.id, '/dav/中文 片名.mp4');

      // 空元素写法 <D:resourcetype></D:resourcetype> 也必须是文件
      final dynamic f2 = rows.firstWhere((dynamic e) => '${e.name}' == 'readme.txt');
      expect(f2.isDir, isFalse);
      expect(f2.size, 42);
    });

    test('深层路径不丢层级', () {
      const String xml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/a/b/c/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response><d:href>/dav/a/b/c/deep.mp4</d:href>
    <d:propstat><d:prop><d:displayname>deep.mp4</d:displayname>
      <d:getcontentlength>7</d:getcontentlength><d:resourcetype/></d:prop></d:propstat>
  </d:response>
</d:multistatus>''';
      final List<dynamic> rows =
          WebDavParser.parse(xml, requestPath: '/dav/a/b/c/');
      expect(rows.length, 1);
      expect(rows.first.name, 'deep.mp4');
      expect(rows.first.id, '/dav/a/b/c/deep.mp4', reason: '层级不能丢');
    });

    test('href 是绝对 URL 时只取 path', () {
      const String xml = '<d:multistatus xmlns:d="DAV:"><d:response>'
          '<d:href>https://nas.local:5006/dav/x/y.mp4</d:href>'
          '<d:propstat><d:prop><d:getcontentlength>9</d:getcontentlength>'
          '<d:resourcetype/></d:prop></d:propstat></d:response></d:multistatus>';
      final List<dynamic> rows = WebDavParser.parse(xml);
      expect(rows.single.id, '/dav/x/y.mp4');
    });
  });

  group('日志脱敏', () {
    test('直链里的 auth_key / sign 不进日志', () {
      const String u =
          'https://cdn.example.com/file.mp4?auth_key=1759000000&sign=abc123&x=1';
      expect(redactUrl(u), 'https://cdn.example.com/file.mp4');
      expect(redactUrl(u).contains('auth_key'), isFalse);
      expect(redactHost(u), 'https://cdn.example.com');
    });

    test('带用户信息的地址不泄漏密码', () {
      expect(redactUrl('https://user:pass@host.example:8443/a/b.mkv?t=1'),
          'https://host.example:8443/a/b.mkv');
    });
  });

  group('异常分类型', () {
    test('AuthExpiredException 与 ResolveException 是两个类型', () {
      expect(const AuthExpiredException(), isA<AppException>());
      expect(const ResolveException(), isA<AppException>());
      expect(const AuthExpiredException().userMessage, contains('登录'));
      expect(const ResolveException().userMessage, contains('直链'));
    });
  });
}
