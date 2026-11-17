import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/parsers/bilibili.dart';
import 'package:yiqikan/data/sources/maccms.dart';
import 'package:yiqikan/data/sources/source_service.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/domain/entities/subtitle.dart';
import 'package:yiqikan/domain/resolver.dart';

void main() {
  group('WBI 签名', () {
    test('官方样例必须得到 8f6f2b5b3d485fe1886cec6a0be8c5d4', () {
      const String imgKey = '7cd084941338484aae1ad9425b84077c';
      const String subKey = '4932caff0ff746eab6f01bf08b70ac45';
      final WbiSignedQuery q = Wbi.sign(
        const <String, String>{
          'foo': '114',
          'bar': '514',
          'zab': '1919810',
        },
        imgKey,
        subKey,
        wtsSeconds: 1702204169,
      );
      expect(q.value,
          'bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4');
    });

    test('mixinKey 取 64 项表的前 32 项', () {
      expect(kMixinKeyEncTab.length, 64);
      expect(
        Wbi.mixinKey('7cd084941338484aae1ad9425b84077c',
            '4932caff0ff746eab6f01bf08b70ac45'),
        'ea1db124af3c7062474693fa704f4ff8',
      );
    });

    test('值里的 !\'()* 只在签名时过滤', () {
      final WbiSignedQuery q = Wbi.sign(
        const <String, String>{'keyword': "a!b'c(d)e*f"},
        '7cd084941338484aae1ad9425b84077c',
        '4932caff0ff746eab6f01bf08b70ac45',
        wtsSeconds: 1702204169,
      );
      expect(q.value.contains('keyword=abcdef'), isTrue);
    });

    test('从 png url 取 key（去目录去扩展名）', () {
      expect(
        Wbi.keyFromUrl(
            'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png'),
        '7cd084941338484aae1ad9425b84077c',
      );
    });
  });

  group('MacCMS 三层分隔', () {
    test(r'$$$ 切线路、# 切集、$ 切名与地址', () {
      final List<MacCmsLine> lines = MacCmsParser.parseLines(
        r'm3u8$$$mp4',
        r'第1集$https://a.example/1.m3u8#第2集$https://a.example/2.m3u8$$$正片$https://b.example/c.mp4',
      );
      expect(lines.length, 2);
      expect(lines[0].name, 'm3u8');
      expect(lines[0].episodes.length, 2);
      expect(lines[0].episodes[0].name, '第1集');
      expect(lines[0].episodes[1].url, 'https://a.example/2.m3u8');
      expect(lines[1].name, 'mp4');
      expect(lines[1].episodes.single.url, 'https://b.example/c.mp4');
    });

    test('第一集不是直链时明确抛 UnsupportedException', () {
      const MacCmsItem item = MacCmsItem(
        id: '1',
        name: '某剧',
        lines: <MacCmsLine>[
          MacCmsLine(name: 'bilibili', episodes: <MacCmsEpisode>[
            MacCmsEpisode(name: '第1集', url: 'https://www.bilibili.com/video/BV1xx'),
          ]),
        ],
      );
      expect(
        () => MacCmsParser.firstEpisodeUrl(item),
        throwsA(isA<UnsupportedException>()),
      );
    });

    test('第一条线路第一集是直链时原样返回', () {
      const MacCmsItem item = MacCmsItem(
        id: '1',
        name: '某剧',
        lines: <MacCmsLine>[
          MacCmsLine(name: 'm3u8', episodes: <MacCmsEpisode>[
            MacCmsEpisode(name: '第1集', url: 'https://a.example/1.m3u8'),
          ]),
        ],
      );
      expect(MacCmsParser.firstEpisodeUrl(item), 'https://a.example/1.m3u8');
    });
  });

  group('解析链', () {
    test('未实现的档位抛 UnsupportedException 而不是返回 null', () async {
      await expectLater(
        const NetdiskStage().tryResolve('https://pan.quark.cn/s/abc'),
        throwsA(isA<UnsupportedException>()),
      );
      await expectLater(
        const EmbyWebdavStage().tryResolve('https://x.example/emby/videos/1'),
        throwsA(isA<UnsupportedException>()),
      );
      await expectLater(
        const SnifferStage().tryResolve('https://x.example/watch/1'),
        throwsA(isA<UnsupportedException>()),
      );
    });

    test('不认识的链接返回 null（交给下一档）', () async {
      expect(await const NetdiskStage().tryResolve('https://a.example/1.mp4'),
          isNull);
      expect(await const EmbyWebdavStage().tryResolve('https://a.example/1.mp4'),
          isNull);
    });

    test('relay 白名单按域名后缀判断', () {
      expect(Resolver.needsRelayFor('https://xy1.szbdyd.com/a.m4s'), isTrue);
      expect(Resolver.needsRelayFor('https://upos-sz-mirror.bilivideo.com/a'), isTrue);
      expect(Resolver.needsRelayFor('https://my.example/a.mp4'), isFalse);
    });
  });

  group('字幕', () {
    test('B 站 JSON 转 SubtitleCue', () {
      final SubtitleData data = SubtitleData.fromBilibiliJson(jsonEncode(<String, Object?>{
        'body': <Object?>[
          <String, Object?>{'from': 0.5, 'to': 3.2, 'content': '第一句'},
          <String, Object?>{'from': 4.0, 'to': 6.0, 'content': '第二句'},
        ],
      }));
      expect(data.cues.length, 2);
      expect(data.textAt(const Duration(seconds: 1)), '第一句');
      expect(data.textAt(const Duration(seconds: 5)), '第二句');
      expect(data.textAt(const Duration(seconds: 9)), isNull);
    });
  });

  group('聚合排序', () {
    test('标题相似度：完全相等 > 包含 > 前缀', () {
      expect(SourceService.titleScore('庆余年', '庆余年'), 1);
      expect(SourceService.titleScore('庆余年', '庆余年 第二季'), 0.9);
      expect(SourceService.titleScore('庆余年', '余年'), 0.8);
      expect(
        SourceService.titleScore('abc', 'abd'),
        lessThan(SourceService.titleScore('abc', 'abc')),
      );
    });
  });
}
