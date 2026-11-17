import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/sniffer/sniff_result.dart';
import 'package:yiqikan/platform/sniffer/sniff_rules.dart';

void main() {
  group('编码还原（04 §8.4）', () {
    test('反斜杠 / unicode / &amp; 全部还原', () {
      expect(
        SniffRules.normalize(r'https:\/\/a.com\/v\/x.m3u8?s=1\u0026t=2'),
        'https://a.com/v/x.m3u8?s=1&t=2',
      );
      expect(SniffRules.normalize('https://a.com/x.mp4?a=1&amp;b=2'),
          'https://a.com/x.mp4?a=1&b=2');
    });
  });

  group('分类', () {
    test('视频扩展名与无扩展名的 CDN 地址', () {
      expect(SniffRules.isVideoUrl('https://a.com/x.m3u8'), isTrue);
      expect(SniffRules.isVideoUrl('https://a.com/x.mp4?sig=1'), isTrue);
      expect(SniffRules.isVideoUrl('https://a.com/live/abc'), isTrue);
      expect(SniffRules.isVideoUrl('https://a.com/x.jpg'), isFalse);
    });

    test('字幕扩展名', () {
      expect(SniffRules.isSubtitleUrl('https://a.com/x.ass'), isTrue);
      expect(SniffRules.isSubtitleUrl('https://a.com/x.SRT?v=2'), isTrue);
      expect(SniffRules.isSubtitleUrl('https://a.com/x.vtt'), isTrue);
      expect(SniffRules.isSubtitleUrl('https://a.com/x.m3u8'), isFalse);
    });

    test('blob:/data: 不收，认不出不收', () {
      expect(SniffRules.fromUrl('blob:https://a.com/1', source: 'l1'), isNull);
      expect(SniffRules.fromUrl('https://a.com/x.png', source: 'l3'), isNull);
    });
  });

  group('via → 六层映射（JS 传钩子名，Dart 定层号）', () {
    test('xhr/fetch/dom 是 L1，perf 是 L2，html 是 L3，iframe 是 L5', () {
      expect(SniffRules.sourceOfVia('xhr'), 'l1');
      expect(SniffRules.sourceOfVia('fetch'), 'l1');
      expect(SniffRules.sourceOfVia('dom'), 'l1');
      expect(SniffRules.sourceOfVia('perf'), 'l2');
      expect(SniffRules.sourceOfVia('html'), 'l3');
      expect(SniffRules.sourceOfVia('iframe'), 'l5');
      expect(SniffRules.sourceOfVia('whatever'), 'l9');
    });

    test('fromVia 用映射后的层号，层号真的参与排序', () {
      final SniffResult l1 = SniffRules.fromVia(
        'https://a.com/1.m3u8',
        via: 'xhr',
      )!;
      final SniffResult l3 = SniffRules.fromVia(
        'https://a.com/2.m3u8',
        via: 'html',
      )!;
      expect(l1.source, 'l1');
      expect(l3.source, 'l3');
      // 同优先级时 L1 在前（之前两个都会落 default 9，顺序随机）
      final List<SniffResult> ranked = SniffRules.rank(<SniffResult>[l3, l1]);
      expect(ranked.first.source, 'l1');
    });

    test('MSE 单独成条，不进排序列表', () {
      final SniffResult? mse = SniffRules.fromVia(
        'blob:https://a.com/9f8e',
        via: 'mse',
      );
      expect(mse, isNotNull);
      expect(mse!.kind, SniffKind.mse);
      expect(
        SniffRules.rank(<SniffResult>[mse]).where(
              (SniffResult r) => r.kind == SniffKind.mse,
            ),
        isEmpty,
      );
    });
  });

  group('去重排序（本轮 9 号：视频在前、字幕在后、各 8 条）', () {
    List<SniffResult> build(List<String> urls, SniffKind kind, String layer) =>
        urls
            .map((String u) => SniffResult(url: u, kind: kind, source: layer))
            .toList();

    test('视频排在字幕前，同类按 m3u8 > mp4 > flv', () {
      final List<SniffResult> ranked = SniffRules.rank(<SniffResult>[
        ...build(<String>['https://a.com/s.srt'], SniffKind.subtitle, 'l1'),
        ...build(<String>[
          'https://a.com/v.flv',
          'https://a.com/v.mp4',
          'https://a.com/v.m3u8',
        ], SniffKind.video, 'l1'),
        ...build(<String>['https://a.com/s.ass'], SniffKind.subtitle, 'l1'),
      ]);

      expect(ranked.length, 5);
      expect(ranked[0].url, 'https://a.com/v.m3u8');
      expect(ranked[1].url, 'https://a.com/v.mp4');
      expect(ranked[2].url, 'https://a.com/v.flv');
      expect(ranked[3].url, 'https://a.com/s.ass');
      expect(ranked[4].url, 'https://a.com/s.srt');
      expect(
          ranked.where((SniffResult r) => r.kind == SniffKind.video).length, 3);
    });

    test('同 URL 只留一条', () {
      final List<SniffResult> ranked = SniffRules.rank(<SniffResult>[
        ...build(<String>['https://a.com/v.m3u8'], SniffKind.video, 'l1'),
        ...build(<String>['https://a.com/v.m3u8'], SniffKind.video, 'l3'),
      ]);
      expect(ranked.length, 1);
      expect(ranked.first.source, 'l1');
    });

    test('每类截断到 8 条', () {
      final List<String> many =
          List<String>.generate(12, (int i) => 'https://a.com/v$i.m3u8');
      final List<SniffResult> ranked =
          SniffRules.rank(build(many, SniffKind.video, 'l1'));
      expect(ranked.length, 8);
    });
  });

  test('注入脚本：XHR / fetch / src setter / MSE / 三次 perf 扫描都在', () {
    const String s = SniffRules.sniffInjectScript;
    expect(s.contains('XMLHttpRequest.prototype.open'), isTrue);
    expect(s.contains('window.fetch'), isTrue);
    expect(s.contains("hookSrc(HTMLMediaElement.prototype, 'dom')"), isTrue);
    expect(s.contains("hookSrc(HTMLTrackElement.prototype, 'dom')"), isTrue);
    expect(s.contains("hookSrc(HTMLSourceElement.prototype, 'dom')"), isTrue);
    expect(s.contains("send(url, 'mse')"), isTrue);
    expect(s.contains('[3000, 8000, 15000]'), isTrue);
    expect(s.contains('querySelectorAll'), isTrue);
    expect(s.contains('getEntriesByType'), isTrue);
    expect(s.contains('callHandler'), isTrue);
  });
}
