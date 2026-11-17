import 'dart:convert';

/// 单条弹幕（03 §4.6 `DanmakuDao` 的载荷元素）。
///
/// 只保留渲染必需的字段：时间点、文本、颜色、模式。
/// 弹幕源千奇百怪（B 站 XML、自建 JSON、本地文件），统一在这里归一。
class DanmakuItem {
  const DanmakuItem({
    required this.time,
    required this.text,
    this.color = '#FFFFFF',
    this.mode = 1,
  });

  /// 出现时间（秒，可带小数）
  final double time;

  /// 文本内容
  final String text;

  /// #RRGGBB
  final String color;

  /// 1 滚动 / 4 底部 / 5 顶部
  final int mode;

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': time,
        'm': text,
        'c': color,
        'p': mode,
      };

  factory DanmakuItem.fromJson(Map<String, dynamic> json) => DanmakuItem(
        time: (json['t'] as num?)?.toDouble() ?? 0,
        text: (json['m'] as String?) ?? '',
        color: (json['c'] as String?) ?? '#FFFFFF',
        mode: (json['p'] as num?)?.toInt() ?? 1,
      );

  @override
  String toString() => 'DanmakuItem($time, ${jsonEncode(text)})';
}

/// 一集弹幕的完整缓存载荷（03 §4.6 `DanmakuDao.get` 的返回类型）。
class DanmakuPayload {
  const DanmakuPayload({
    required this.mediaId,
    required this.episodeIndex,
    required this.items,
    required this.fetchedAt,
    required this.expiresAt,
  });

  final String mediaId;
  final int episodeIndex;
  final List<DanmakuItem> items;
  final DateTime fetchedAt;
  final DateTime expiresAt;

  int get count => items.length;

  /// 是否还在 TTL 内
  bool get isValid => expiresAt.isAfter(DateTime.now());

  /// 落库用的 JSON 数组字符串
  String encodeItems() =>
      jsonEncode(items.map((DanmakuItem e) => e.toJson()).toList());

  /// 从库里的 payload 字符串还原
  static List<DanmakuItem> decodeItems(String payload) {
    final Object? raw = jsonDecode(payload);
    if (raw is! List) return const <DanmakuItem>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DanmakuItem.fromJson)
        .toList(growable: false);
  }

  @override
  String toString() =>
      'DanmakuPayload($mediaId#$episodeIndex, count: $count, expiresAt: $expiresAt)';
}
