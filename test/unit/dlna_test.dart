import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/dlna/dlna_sender.dart';

/// M10 B 组：DLNA 元数据与 SOAP 转义。
///
/// 投屏最容易坏在 XML 上：URL 里的 `&`（播放列表/查询串常见）不转义，
/// 电视会直接拒收 501/400，而本地测试看不出来。这组用例把 play() 用的
/// 同一个 _didl / _xml 拉出来断。
void main() {
  test('DIDL-Lite 带 protocolInfo 且 URL 已转义', () {
    final String didl = dlnaDidlFor(
      'http://10.0.0.2:8080/local/media/play?path=/sdcard/Movies/a&b.mkv',
      'a & b',
    );
    expect(didl, contains('<DIDL-Lite'));
    expect(didl, contains('urn:schemas-upnp-org:metadata-1-0/DIDL-Lite'));
    expect(didl, contains('protocolInfo="http-get:*:video/*:*"'));
    // 原始 & 必须不存在，只允许 &amp;
    expect(didl.contains('a&b.mkv'), isFalse);
    expect(didl, contains('a&amp;b.mkv'));
    expect(didl, contains('<dc:title>a &amp; b</dc:title>'));
  });

  test('五个 XML 特殊字符都被转义', () {
    expect(dlnaEscape('a&b<c>d"e\'f'),
        'a&amp;b&lt;c&gt;d&quot;e&apos;f');
  });

  test('纯 ASCII URL 原样保留（不乱改大小写/斜杠）', () {
    const String url =
        'http://127.0.0.1:8080/local/media/play?path=%2Fsdcard%2FMovies%2Fp.mkv';
    expect(dlnaEscape(url), url);
    expect(dlnaDidlFor(url, 'p.mkv'), contains(url));
  });
}
