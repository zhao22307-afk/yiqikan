/// 嗅探结果的类型（04 §8.3 + 本轮 9 号要求）
///
/// 视频和字幕走同一条六层链，但进列表后要分开排：
/// 视频在前、字幕在后，各自去重后最多 8 条。
enum SniffKind {
  video('视频'),
  subtitle('字幕'),

  /// 页面用 MSE（blob:）喂播放器，地址取不出来。
  /// 这是「没找到」之外的第 4 种情况，UI 要单独说一句。
  mse('MSE');

  const SniffKind(this.label);

  final String label;
}

/// 嗅探命中的一条地址
class SniffResult {
  const SniffResult({
    required this.url,
    required this.kind,
    required this.source,
    this.pageUrl = '',
    this.headers = const <String, String>{},
  });

  /// 绝对地址（已做过编码还原）
  final String url;

  final SniffKind kind;

  /// 哪一层抓到的：l0 / l1 / l2 / l3 / l4 / l5
  final String source;

  /// 抓它的时候所在的页面地址（Referer 就从这来）
  final String pageUrl;

  /// 从页面带出来的请求头（Referer / UA / Cookie）
  final Map<String, String> headers;

  SniffResult withHeaders(Map<String, String> h) => SniffResult(
        url: url,
        kind: kind,
        source: source,
        pageUrl: pageUrl,
        headers: h,
      );

  @override
  String toString() => 'SniffResult(${kind.name}, $source, $url)';
}
