import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// ASS/SSA 的样式（[V4+ Styles] 里的 Style 行）。
///
/// 只保留渲染真正用得到的字段：字号、主色、描边色、粗斜体、对齐、边距。
/// 颜色是 ASS 的 `&HAABBGGRR` 口径，这里只存 RGB（0xRRGGBB），alpha 单独处理。
@immutable
class AssStyle {
  const AssStyle({
    this.fontSize = 42,
    this.primaryColor = 0xFFFFFF,
    this.outlineColor = 0x000000,
    this.italic = false,
    this.bold = false,
    this.outline = 2,
    this.alignment = 2,
    this.marginL = 10,
    this.marginR = 10,
    this.marginV = 10,
  });

  final int fontSize;
  final int primaryColor;
  final int outlineColor;
  final bool italic;
  final bool bold;
  final double outline;

  /// 1–9 九宫格（1 左下、2 下中、3 右下、4 左中、5 正中、6 右中、7 左上、8 上中、9 右上）
  final int alignment;
  final int marginL;
  final int marginR;
  final int marginV;

  static const AssStyle fallback = AssStyle();

  AssStyle copyWith({
    int? fontSize,
    int? primaryColor,
    int? outlineColor,
    bool? italic,
    bool? bold,
    double? outline,
    int? alignment,
  }) {
    return AssStyle(
      fontSize: fontSize ?? this.fontSize,
      primaryColor: primaryColor ?? this.primaryColor,
      outlineColor: outlineColor ?? this.outlineColor,
      italic: italic ?? this.italic,
      bold: bold ?? this.bold,
      outline: outline ?? this.outline,
      alignment: alignment ?? this.alignment,
      marginL: marginL,
      marginR: marginR,
      marginV: marginV,
    );
  }
}

/// 一条字幕。
///
/// `text` 是剥掉覆盖标签后的纯文本（兜底用）；
/// `raw` 是原始正文（保留 `{\an8}` 这类标签），自绘层按需解析；
/// `style` 是 ASS 样式名，`ass` 是查表后的样式。
@immutable
class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
    this.raw,
    this.style = 'Default',
    this.ass,
  });

  final Duration start;
  final Duration end;
  final String text;
  final String? raw;
  final String style;
  final AssStyle? ass;

  bool covers(Duration pos) => pos >= start && pos < end;
}

/// 解析好的字幕文件：SRT / VTT / ASS 都落成同一份 cue 列表。
///
/// 为什么要在 Flutter 层自绘：这套 libmpv + media_kit 2.0.1 在 Android 上的
/// OSD/字幕图层画不出像素（15 §A5 的四步排查全做过：osd-level、sub-visibility、
/// sub-ass=no、sub-pos/margin、80 号红字居中；`sid=1`、`sub-text` 有中文，屏幕就是不出字）。
@immutable
class SubtitleData {
  const SubtitleData(
    this.cues, {
    this.playResX = 384,
    this.playResY = 288,
    this.styles = const <String, AssStyle>{},
  });

  final List<SubtitleCue> cues;

  /// ASS 的坐标系（`[Script Info]` 的 PlayResX / PlayResY）。
  /// `\pos(x,y)` 是相对这两个值的，不是屏幕像素 —— 不换算 4K 片源会把字幕挤到左上角。
  final int playResX;
  final int playResY;
  final Map<String, AssStyle> styles;

  static const SubtitleData empty = SubtitleData(<SubtitleCue>[]);

  bool get isEmpty => cues.isEmpty;

  /// 从本地文件读（调用方负责先把 GBK 之类转成 UTF-8）。
  static Future<SubtitleData> load(String pathOrUri) async {
    final String path = pathOrUri.startsWith('file://')
        ? Uri.parse(pathOrUri).toFilePath()
        : pathOrUri;
    final List<int> bytes = await File(path).readAsBytes();
    // 走到这里的文件都已经是 UTF-8（GBK 在 SubtitleLoader 里转过），
    // 但历史字幕偶尔带 BOM，用 allowMalformed 兜住，不让一行坏字节毁掉整块。
    final String text = utf8.decode(bytes, allowMalformed: true);
    return SubtitleData.parse(text);
  }

  static SubtitleData parse(String text) {
    final _Parsed p = _parseAll(text);
    return SubtitleData(
      p.cues,
      playResX: p.playResX,
      playResY: p.playResY,
      styles: p.styles,
    );
  }

  /// B 站 `/x/player/v2` 的字幕 JSON：`{body:[{from,to,content}]}`（14 §1.5）。
  static SubtitleData fromBilibiliJson(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('B 站字幕不是 JSON 对象');
    }
    final Object? body = decoded['body'];
    if (body is! List<Object?>) return SubtitleData.empty;
    final List<SubtitleCue> cues = <SubtitleCue>[];
    for (final Object? item in body) {
      if (item is! Map<String, Object?>) continue;
      final double from = (item['from'] as num?)?.toDouble() ?? -1;
      final double to = (item['to'] as num?)?.toDouble() ?? -1;
      final String content = (item['content'] as String?)?.trim() ?? '';
      if (from < 0 || to <= from || content.isEmpty) continue;
      cues.add(SubtitleCue(
        start: Duration(milliseconds: (from * 1000).round()),
        end: Duration(milliseconds: (to * 1000).round()),
        text: content,
      ));
    }
    cues.sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));
    return SubtitleData(cues);
  }

  static _Parsed _parseAll(String raw) {
    final List<SubtitleCue> cues = <SubtitleCue>[];
    final Map<String, AssStyle> styles = <String, AssStyle>{};
    int playResX = 384;
    int playResY = 288;

    final List<String> lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    int i = 0;
    while (i < lines.length) {
      final String line = lines[i].trim();

      if (line.startsWith('PlayResX:')) {
        playResX = int.tryParse(line.substring('PlayResX:'.length).trim()) ?? playResX;
        i++;
        continue;
      }
      if (line.startsWith('PlayResY:')) {
        playResY = int.tryParse(line.substring('PlayResY:'.length).trim()) ?? playResY;
        i++;
        continue;
      }
      // Style: Name,Fontname,Fontsize,Primary,Secondary,Outline,Back,Bold,Italic,
      //        Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,
      //        OutlineW,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
      if (line.startsWith('Style:')) {
        final AssStyle? st = _assStyle(line.substring(6));
        if (st != null) styles[line.substring(6).split(',').first.trim()] = st;
        i++;
        continue;
      }
      // ASS/SSA：Dialogue: Layer,Start,End,Style,Name,ML,MR,MV,Effect,Text
      if (line.startsWith('Dialogue:')) {
        final SubtitleCue? cue = _assCue(line.substring('Dialogue:'.length));
        if (cue != null) cues.add(cue);
        i++;
        continue;
      }

      final int arrow = line.indexOf('-->');
      if (arrow > 0) {
        final Duration? start = _time(line.substring(0, arrow).trim());
        final String right = line.substring(arrow + 3).trim();
        final Duration? end = _time(right.split(' ').first);
        if (start != null && end != null) {
          final List<String> body = <String>[];
          i++;
          while (i < lines.length &&
              lines[i].trim().isNotEmpty &&
              !lines[i].contains('-->')) {
            body.add(lines[i].trim());
            i++;
          }
          if (body.isNotEmpty) {
            cues.add(SubtitleCue(
              start: start,
              end: end,
              text: body.join('\n'),
            ));
          }
          continue;
        }
      }
      i++;
    }
    cues.sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));
    return _Parsed(cues, styles, playResX, playResY);
  }

  static AssStyle? _assStyle(String body) {
    final List<String> f = body.split(',');
    if (f.length < 23) return null;
    int color(String v) => _assColor(v);
    return AssStyle(
      fontSize: int.tryParse(f[2].trim()) ?? 42,
      primaryColor: color(f[3]),
      outlineColor: color(f[5]),
      bold: (int.tryParse(f[7].trim()) ?? 0) < 0,
      italic: (int.tryParse(f[8].trim()) ?? 0) < 0,
      outline: double.tryParse(f[16].trim()) ?? 2,
      alignment: int.tryParse(f[18].trim()) ?? 2,
      marginL: int.tryParse(f[19].trim()) ?? 10,
      marginR: int.tryParse(f[20].trim()) ?? 10,
      marginV: int.tryParse(f[21].trim()) ?? 10,
    );
  }

  /// `&H00FFFFFF` / `HFFFFFF&` / `#RRGGBB` → 0xRRGGBB（ASS 是 BBGGRR 字节序）
  static int _assColor(String raw) {
    String v = raw.trim();
    if (v.startsWith('#') && v.length >= 7) {
      return int.tryParse(v.substring(1, 7), radix: 16) ?? 0xFFFFFF;
    }
    v = v.replaceAll('&', '').replaceAll('H', '').replaceAll('h', '');
    if (v.length < 6) return 0xFFFFFF;
    final int bgr = int.tryParse(v.substring(v.length - 6), radix: 16) ?? 0xFFFFFF;
    final int b = (bgr >> 16) & 0xFF;
    final int g = (bgr >> 8) & 0xFF;
    final int r = bgr & 0xFF;
    return (r << 16) | (g << 8) | b;
  }

  /// 解析一条 ASS Dialogue：前 9 个逗号是元数据，第 10 段起是正文（正文里可能有逗号）。
  static SubtitleCue? _assCue(String body) {
    final List<String> f = <String>[];
    int from = 0;
    for (int k = 0; k < 9; k++) {
      final int comma = body.indexOf(',', from);
      if (comma < 0) return null;
      f.add(body.substring(from, comma));
      from = comma + 1;
    }
    f.add(body.substring(from));
    if (f.length < 10) return null;
    final Duration? start = _time(f[1].trim());
    final Duration? end = _time(f[2].trim());
    if (start == null || end == null || end <= start) return null;
    final String rawText = f[9];
    final String text = rawText
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .trim();
    if (text.isEmpty) return null;
    return SubtitleCue(
      start: start,
      end: end,
      text: text,
      raw: rawText,
      style: f[3].trim().isEmpty ? 'Default' : f[3].trim(),
    );
  }

  /// `00:00:01,500` / `00:00:01.500` / `01:02.500`
  static Duration? _time(String raw) {
    final String s = raw.replaceAll(',', '.');
    final List<String> parts = s.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final double sec = double.tryParse(parts.last) ?? -1;
    if (sec < 0) return null;
    final int min = int.tryParse(parts[parts.length - 2]) ?? -1;
    if (min < 0) return null;
    final int hour = parts.length == 3 ? (int.tryParse(parts.first) ?? 0) : 0;
    return Duration(
      milliseconds:
          (hour * 3600 * 1000 + min * 60 * 1000 + (sec * 1000).round()),
    );
  }

  /// 当前时间点的第一条字幕（兼容老调用；自绘层请用 [at] 取全部同屏条）。
  String? textAt(Duration position) {
    for (final SubtitleCue c in cues) {
      if (c.covers(position)) return c.text;
    }
    return null;
  }

  /// 当前时间点全部同屏字幕 —— ASS 里「顶部注释 + 底部对白」天然并存，
  /// 只取第一条就是漏字。
  List<SubtitleCue> at(Duration position) =>
      cues.where((SubtitleCue c) => c.covers(position)).toList();

  /// 取这条 cue 的样式（先查内联 `ass`，再查 styles 表，最后兜底）
  AssStyle styleOf(SubtitleCue cue) =>
      cue.ass ?? styles[cue.style] ?? AssStyle.fallback;

  /// 字幕文件里所有出现过的样式名（调试用）
  @override
  String toString() => 'SubtitleData(cues=${cues.length}, '
      'playRes=${playResX}x$playResY, styles=${styles.length})';
}

class _Parsed {
  const _Parsed(this.cues, this.styles, this.playResX, this.playResY);
  final List<SubtitleCue> cues;
  final Map<String, AssStyle> styles;
  final int playResX;
  final int playResY;
}
