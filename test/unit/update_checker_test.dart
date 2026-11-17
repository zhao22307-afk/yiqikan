import 'package:flutter_test/flutter_test.dart';

import 'package:yiqikan/core/update/update_checker.dart';

void main() {
  group('compareVersions', () {
    test('三段语义比较', () {
      expect(compareVersions('0.2.0', '0.1.9'), 1);
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.0.0', '1.0.1'), -1);
      expect(compareVersions('2', '1.9.9'), 1);
    });

    test('缺段补 0，预发布后缀忽略', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.0-beta.3', '1.2.0'), 0);
      expect(compareVersions('1.2.1-beta', '1.2.0'), 1);
      expect(compareVersions('v1.3.0', '1.2.9'), 1);
    });
  });

  group('pickNewer', () {
    final UpdateInfo info = UpdateInfo(
      version: '0.2.0',
      url: 'https://example.com/a.apk',
      sha256: List<String>.filled(64, 'a').join(),
      size: 1024,
    );

    test('更高才返回', () {
      expect(pickNewer(info, '0.1.0'), same(info));
      expect(pickNewer(info, '0.2.0'), isNull);
      expect(pickNewer(info, '0.3.0'), isNull);
      expect(pickNewer(null, '0.1.0'), isNull);
    });
  });

  group('UpdateInfo.fromJson', () {
    test('正常 feed', () {
      final UpdateInfo? i = UpdateInfo.fromJson(<String, Object?>{
        'version': '0.2.0',
        'url': 'https://x/yqk-0.2.0.apk',
        'sha256': 'B' * 64,
        'size': 51860417,
        'notes': '修了投屏',
      });
      expect(i, isNotNull);
      expect(i!.version, '0.2.0');
      expect(i.sha256, 'b' * 64, reason: '大小写统一成小写再比');
      expect(i.hasHash, isTrue);
      expect(i.size, 51860417);
      expect(UpdateInfo.sizeText(i.size), '49.5 MB');
    });

    test('缺 version / url 返回 null', () {
      expect(UpdateInfo.fromJson(<String, Object?>{'url': 'https://x'}), isNull);
      expect(UpdateInfo.fromJson(<String, Object?>{'version': '0.2.0'}), isNull);
      expect(UpdateInfo.fromJson('not a map'), isNull);
    });

    test('没给 sha256 时 hasHash=false（仍然允许装，只少一道校验）', () {
      final UpdateInfo? i = UpdateInfo.fromJson(<String, Object?>{
        'version': '0.2.0',
        'url': 'https://x/a.apk',
      });
      expect(i!.hasHash, isFalse);
      expect(UpdateInfo.sizeText(0), '未知大小');
    });
  });
}
