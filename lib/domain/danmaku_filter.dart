/// H3 弹幕过滤：纯规则 + 统计，不依赖 Flutter，方便单测。
///
/// 设计取舍（10 号 :181 的 H3 原文只说「本地小模型或规则+统计」）：
/// 本版走规则 + 窗口统计，模型留给后续。五条规则都能单独关掉，默认全开。
library;

enum FilterReason { none, tooShort, tooLong, repeat, spam, spoiler }

/// 命中原因 + 命中的片段（给日志看，方便定位是哪条规则）
class FilterResult {
  const FilterResult(this.reason, [this.hit]);
  final FilterReason reason;
  final String? hit;

  bool get blocked => reason != FilterReason.none;

  @override
  String toString() => blocked ? '${reason.name}${hit == null ? '' : '($hit)'}' : 'none';
}

/// 五条规则的开关。全部默认开。
class FilterOptions {
  const FilterOptions({
    this.tooShort = true,
    this.tooLong = true,
    this.repeat = true,
    this.spam = true,
    this.spoiler = true,
  });

  final bool tooShort;
  final bool tooLong;
  final bool repeat;
  final bool spam;
  final bool spoiler;

  bool get any => tooShort || tooLong || repeat || spam || spoiler;

  FilterOptions copyWith({
    bool? tooShort,
    bool? tooLong,
    bool? repeat,
    bool? spam,
    bool? spoiler,
  }) =>
      FilterOptions(
        tooShort: tooShort ?? this.tooShort,
        tooLong: tooLong ?? this.tooLong,
        repeat: repeat ?? this.repeat,
        spam: spam ?? this.spam,
        spoiler: spoiler ?? this.spoiler,
      );

  Map<String, bool> toJson() => <String, bool>{
        'tooShort': tooShort,
        'tooLong': tooLong,
        'repeat': repeat,
        'spam': spam,
        'spoiler': spoiler,
      };

  static FilterOptions fromJson(Object? raw) {
    if (raw is! Map) return const FilterOptions();
    bool v(String k, bool def) => raw[k] is bool ? raw[k]! as bool : def;
    return FilterOptions(
      tooShort: v('tooShort', true),
      tooLong: v('tooLong', true),
      repeat: v('repeat', true),
      spam: v('spam', true),
      spoiler: v('spoiler', true),
    );
  }
}

/// 剧透词表：30 个以内，只收「说出来就一定剧透」的短句。
const List<String> kSpoilerWords = <String>[
  '凶手是',
  '凶手就',
  '结局是',
  '结局就',
  '他死了',
  '她死了',
  '他们都死了',
  '最后死',
  '反转',
  '其实是他',
  '其实是女主',
  '真凶',
  '幕后黑手',
  '彩蛋是',
  '剧透',
  'boss 是',
  'boss是',
  '大结局',
  '主角死',
  '男主死',
  '女主死',
  '自杀结局',
  '双胞胎',
  '是梦',
  '回忆杀',
];

/// 全局过滤入口（无状态，纯函数）。
class DanmakuFilter {
  const DanmakuFilter._();

  static const int maxLen = 50;
  static const int minLen = 2;
  static const int repeatWindowSec = 10;
  static const int repeatTimes = 3;
  static const int spamRunLen = 6;

  /// [recent] 是「最近一小段窗口内的历史文本」（调用方自己维护，按时间正序）。
  /// [windowSec] 只用于文档说明：调用方传入 recent 时就该是这段时间内的。
  static FilterResult check(
    String text,
    List<String> recent, {
    int windowSec = repeatWindowSec,
    FilterOptions options = const FilterOptions(),
  }) {
    final String t = text.trim();
    if (options.tooShort && t.runes.length < minLen) {
      return const FilterResult(FilterReason.tooShort);
    }
    if (options.tooLong && t.runes.length > maxLen) {
      return FilterResult(FilterReason.tooLong, '${t.runes.length}');
    }
    if (options.spam) {
      final String? run = _longestRun(t);
      if (run != null && run.runes.length >= spamRunLen) {
        return FilterResult(FilterReason.spam, run);
      }
      if (_punctRatio(t) >= 0.9 && t.runes.length >= 3) {
        return FilterResult(FilterReason.spam, 'punct');
      }
    }
    if (options.repeat) {
      final int same = recent.where((String e) => e.trim() == t).length;
      if (same + 1 >= repeatTimes) {
        return FilterResult(FilterReason.repeat, '${same + 1}x/${windowSec}s');
      }
    }
    if (options.spoiler) {
      final String lower = t.toLowerCase();
      for (final String w in kSpoilerWords) {
        if (lower.contains(w.toLowerCase())) {
          return FilterResult(FilterReason.spoiler, w);
        }
      }
    }
    return const FilterResult(FilterReason.none);
  }

  /// 最长「同一个字符连续出现」的片段；没有连续重复返回 null。
  static String? _longestRun(String s) {
    final List<int> r = s.runes.toList();
    if (r.isEmpty) return null;
    String? best;
    int i = 0;
    while (i < r.length) {
      int j = i + 1;
      while (j < r.length && r[j] == r[i]) {
        j++;
      }
      if (j - i >= 2) {
        final String seg = String.fromCharCodes(r.sublist(i, j));
        if (best == null || seg.runes.length > best.runes.length) best = seg;
      }
      i = j;
    }
    return best;
  }

  /// 标点/符号占比。用来挡「！！！！！」这类。
  static double _punctRatio(String s) {
    final List<int> r = s.runes.toList();
    if (r.isEmpty) return 0;
    int punct = 0;
    for (final int c in r) {
      final bool isDigit = c >= 0x30 && c <= 0x39;
      final bool isAsciiAlpha = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
      final bool isCjk = c >= 0x4E00 && c <= 0x9FFF;
      final bool isKana = (c >= 0x3040 && c <= 0x30FF);
      final bool isHangul = c >= 0xAC00 && c <= 0xD7AF;
      if (!(isDigit || isAsciiAlpha || isCjk || isKana || isHangul)) punct++;
    }
    return punct / r.length;
  }
}
