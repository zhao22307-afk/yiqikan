import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/features/player/subtitle_scanner.dart';

void main() {
  group('SubtitleScanner.langOf', () {
    test('中英文与日文都能认出来', () {
      expect(SubtitleScanner.langOf('zh'), 'zh');
      expect(SubtitleScanner.langOf('zh-CN'), 'zh');
      expect(SubtitleScanner.langOf('简体'), 'zh');
      expect(SubtitleScanner.langOf('chs'), 'zh');
      expect(SubtitleScanner.langOf('zh-TW'), 'zh-Hant');
      expect(SubtitleScanner.langOf('繁体'), 'zh-Hant');
      expect(SubtitleScanner.langOf('eng'), 'en');
      expect(SubtitleScanner.langOf('英文'), 'en');
      expect(SubtitleScanner.langOf('jp'), 'ja');
      expect(SubtitleScanner.langOf('日文'), 'ja');
    });

    test('认不出来的一律当作 und', () {
      expect(SubtitleScanner.langOf(''), 'und');
      expect(SubtitleScanner.langOf('xx'), 'und');
      expect(SubtitleScanner.langOf('5.1'), 'und');
    });
  });

  test('labelOf 把语言码翻成人话，未知的原样返回', () {
    expect(SubtitleScanner.labelOf('zh'), '简体中文');
    expect(SubtitleScanner.labelOf('zh-Hant'), '繁体中文');
    expect(SubtitleScanner.labelOf('en'), '英文');
    expect(SubtitleScanner.labelOf('ja'), '日文');
    expect(SubtitleScanner.labelOf('und'), '未标注语言');
    expect(SubtitleScanner.labelOf('ko'), 'ko');
  });

  test('videoPathOf 认 file:// 与 /local/media/play 两种地址', () {
    // 注意：Uri.toFilePath() 在 Windows 上会给出反斜杠，真机是 /data/...；
    // 这里只断言「解出了本地文件路径」这一件事，不锁分隔符。
    final String? p1 = SubtitleScanner.videoPathOf(
        'file:///data/user/0/top.yiqikan.app.debug/files/sample.mp4');
    expect(p1, isNotNull);
    expect(p1!.endsWith('sample.mp4'), isTrue);
    expect(p1.contains('file://'), isFalse);
    expect(
      SubtitleScanner.videoPathOf(
          'http://127.0.0.1:8080/local/media/play?path=%2Fsdcard%2FMovies%2Fpromo_long.mkv'),
      '/sdcard/Movies/promo_long.mkv',
    );
    expect(SubtitleScanner.videoPathOf('https://example.com/a.m3u8'), isNull);
    expect(SubtitleScanner.isLocal('/sdcard/Movies/a.mkv'), isTrue);
  });
}
