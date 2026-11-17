import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/subtitle.dart';
import 'player_controller.dart';

/// 字幕的数据结构在 domain 层（数据层与 UI 层共用），这里再导出一次，
/// 老引用 `import 'subtitle_overlay.dart'` 的地方不用改。
export '../../domain/entities/subtitle.dart';

/// 盖在视频上层的字幕（跟着播放位置走，带描边，不改任何 mpv 参数）。
///
/// 为什么自绘：这套 libmpv + media_kit 2.0.1 在 Android 上字幕层不出像素，
/// 四步排查见 15 §A5。
///
/// 支持这些 ASS 标签（番剧字幕 90% 就这些）：
/// `\an1–\an9`、`\pos(x,y)`、`\i1/\i0`、`\b1/\b0`、`\c/\1c&HBBGGRR&`、
/// `\alpha/\1a&HAA&`、`\fs{N}`、`\N` 换行。
/// 明确不做（剥掉标签保留文本）：`\move`、`\clip`、`\iclip`、`\t(...)`、
/// `\p1–\p9` 矢量绘图、`\k/\kf/\ko` 卡拉 OK。
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.controller,
    required this.data,
    this.bottomPadding = 0,
  });

  final PlayerController controller;
  final SubtitleData data;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? _) {
          final Duration pos = controller.position +
              Duration(milliseconds: (controller.subDelay * 1000).round());
          final List<SubtitleCue> live = data.at(pos);
          if (live.isEmpty) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double width = c.maxWidth;
              final double height = c.maxHeight;
              final TextScaler scaler = MediaQuery.textScalerOf(context);
              return Stack(
                children: <Widget>[
                  for (final SubtitleCue cue in live)
                    _buildCue(cue, width, height, scaler),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCue(
    SubtitleCue cue,
    double width,
    double height,
    TextScaler textScaler,
  ) {
    final AssStyle base = data.styleOf(cue);
    final _ParsedText parsed = _ParsedText.parse(
      cue.raw ?? cue.text,
      base,
      controller.subFontSize,
    );
    final _AssOverride ov = parsed.override;
    final int align = ov.alignment ?? base.alignment;
    // PlayRes 的「像素」按窗口宽度换算成逻辑像素；垂直用同一比例，避免非等比拉伸
    // PlayRes 按「统一比例 + letterbox 居中」换算（libass 语义）：
    // scale 取 min(scaleX, scaleY)，避免水平/垂直各按自己比例拉伸；
    // ox/oy 是 PlayRes 画布在视频区里的居中偏移，\pos 与 margin 都要带它。
    final double scaleX = width / data.playResX;
    final double scaleY = height / data.playResY;
    final double scale = math.min(scaleX, scaleY).clamp(0.15, 12.0);
    final double ox = (width - data.playResX * scale) / 2;
    final double oy = (height - data.playResY * scale) / 2;

    final TextSpan span = TextSpan(
      children: <InlineSpan>[
        for (final _Run r in parsed.runs)
          TextSpan(
            text: r.text,
            style: TextStyle(
              // \alpha / \1a 落在文字本身的不透明度上（之前只给了描边，字还是实心）
              color: (r.color ?? _colorOf(base.primaryColor))
                  .withValues(alpha: r.opacity ?? 1.0),
              fontSize: (r.fontSize ?? base.fontSize) * scale,
              height: 1.25,
              fontStyle: (r.italic ?? base.italic)
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontWeight: (r.bold ?? base.bold)
                  ? FontWeight.w700
                  : FontWeight.w600,
              shadows: <Shadow>[
                // 用描边色做四向阴影，等价于 ASS 的 OutlineColour
                for (final Offset o in const <Offset>[
                  Offset(-1.2, 0),
                  Offset(1.2, 0),
                  Offset(0, -1.2),
                  Offset(0, 1.2),
                ])
                  Shadow(
                    offset: o,
                    blurRadius: 2 * base.outline,
                    color: _colorOf(base.outlineColor)
                        .withValues(alpha: r.opacity ?? 1.0),
                  ),
              ],
            ),
          ),
      ],
    );
    if (kDebugMode && parsed.runs.any((_Run r) => (r.opacity ?? 1.0) < 0.999)) {
      final double op = parsed.runs
          .map((_Run r) => r.opacity ?? 1.0)
          .reduce((double a, double b) => a < b ? a : b);
      final String label = (cue.text.trim().isEmpty ? '?' : cue.text.trim());
      debugPrint(
        '[YQK-SUB] cue=${label.length > 12 ? label.substring(0, 12) : label} opacity=${op.toStringAsFixed(3)}',
      );
    }
    final TextAlign textAlign = _textAlignOf(align);

    // \pos(x,y)：绝对坐标 + 锚点对齐。
    // 先用 TextPainter 量出真实尺寸（带同一个 textScaler），再用 Positioned 摆；
    // 不用 Align 表达绝对坐标——Align 的 childLeft=(C-W)*(x+1)/2 依赖未固定的子宽 W，解不出唯一解。
    if (ov.pos != null) {
      // 绝对像素 = 居中偏移 + PlayRes 坐标 * 统一比例（不用 fx/fy 反推）
      final double px = ox + ov.pos!.dx * scale;
      final double py = oy + ov.pos!.dy * scale;
      final Offset anchor = _anchorOf(align);
      final TextPainter tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textAlign: textAlign,
        textScaler: textScaler,
        maxLines: 4,
      )..layout(maxWidth: width);
      final double tw = tp.width;
      final double th = tp.height;
      tp.dispose();
      final double left =
          (px - anchor.dx * tw).clamp(0.0, (width - tw) > 0 ? width - tw : 0.0);
      final double top =
          (py - anchor.dy * th).clamp(0.0, (height - th) > 0 ? height - th : 0.0);
      if (kDebugMode) {
        debugPrint(
          '[YQK-SUB] cue=${cue.text.characters.take(6)} pos=(${px.toStringAsFixed(1)},'
          '${py.toStringAsFixed(1)}) left=${left.toStringAsFixed(1)} '
          'top=${top.toStringAsFixed(1)} scale=${scale.toStringAsFixed(4)} '
          'ox=${ox.toStringAsFixed(1)} oy=${oy.toStringAsFixed(1)} '
          'W=${width.toStringAsFixed(1)} H=${height.toStringAsFixed(1)}',
        );
      }
      return Positioned(
        left: left,
        top: top,
        child: SizedBox(
          width: tw,
          height: th,
          child: RichText(
            textAlign: textAlign,
            textScaler: textScaler,
            text: span,
          ),
        ),
      );
    }

    // 没 \pos 就按 \an 九宫格贴边：1–3 贴底、4–6 居中、7–9 贴顶
    final double m = base.marginV * scale;
    final double ml = base.marginL * scale;
    final double mr = base.marginR * scale;

    final bool top = align >= 7;
    final bool middle = align >= 4 && align <= 6;
    final bool left = align == 1 || align == 4 || align == 7;
    final bool right = align == 3 || align == 6 || align == 9;
    if (kDebugMode) {
      // 用户要看数：scale / ox / oy / m / py（py 对非 pos 的贴底 cue 就是 height - m）
      debugPrint(
        '[YQK-SUBBOX] align=$align scale=${scale.toStringAsFixed(5)} '
        'ox=${ox.toStringAsFixed(3)} oy=${oy.toStringAsFixed(3)} '
        'm=${m.toStringAsFixed(3)} ml=${ml.toStringAsFixed(3)} '
        'mr=${mr.toStringAsFixed(3)} '
        'py=${(top ? m : height - m).toStringAsFixed(3)} '
        'W=${width.toStringAsFixed(1)} H=${height.toStringAsFixed(1)}',
      );
    }
    // \frz 旋转只作用在文字层，不参与 Positioned 的 left/top 计算，
    // 否则旋转后的包围盒会把整行挪位（libass 里 \pos/\an 的锚点也不随旋转走）。
    Widget text = RichText(textAlign: textAlign, text: span);
    final double deg = ov.rotateZ ?? 0;
    if (deg != 0) {
      text = Transform.rotate(
        angle: deg * math.pi / 180,
        alignment: Alignment.center,
        child: text,
      );
    }

    // 边距都从「PlayRes 画布」量起：画布左/上边界是 ox/oy，所以贴边要再加 ox/oy 的补偿
    final double edgeL = ox + ml;
    final double edgeR = ox + mr;
    final double edgeV = oy + m;
    if (middle) {
      return Positioned(
        left: left ? edgeL : (right ? null : 0),
        right: right ? edgeR : (left ? null : 0),
        top: 0,
        bottom: 0,
        child: Align(
          alignment: left
              ? Alignment.centerLeft
              : (right ? Alignment.centerRight : Alignment.center),
          child: text,
        ),
      );
    }
    return Positioned(
      left: left ? edgeL : (right ? null : 0),
      right: right ? edgeR : (left ? null : 0),
      top: top ? edgeV : null,
      bottom: top ? null : (edgeV + bottomPadding),
      child: Align(
        alignment: left
            ? Alignment.centerLeft
            : (right ? Alignment.centerRight : Alignment.center),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width - ml - mr),
          child: text,
        ),
      ),
    );
  }

  static TextAlign _textAlignOf(int an) {
    if (an == 1 || an == 4 || an == 7) return TextAlign.left;
    if (an == 3 || an == 6 || an == 9) return TextAlign.right;
    return TextAlign.center;
  }

  /// 九宫格锚点（0,0 左上；1,1 右下）。\pos 以这个点为基准。
  static Offset _anchorOf(int an) {
    switch (an) {
      case 1:
        return const Offset(0, 1);
      case 2:
        return const Offset(0.5, 1);
      case 3:
        return const Offset(1, 1);
      case 4:
        return const Offset(0, 0.5);
      case 5:
        return const Offset(0.5, 0.5);
      case 6:
        return const Offset(1, 0.5);
      case 7:
        return const Offset(0, 0);
      case 8:
        return const Offset(0.5, 0);
      case 9:
        return const Offset(1, 0);
      default:
        return const Offset(0.5, 1);
    }
  }

  static Color _colorOf(int rgb) => Color(0xFF000000 | (rgb & 0xFFFFFF));
}

/// 一段同样式文本
class _Run {
  _Run(this.text, {this.color, this.italic, this.bold, this.fontSize, this.opacity});
  final String text;
  final Color? color;
  final bool? italic;
  final bool? bold;
  final double? fontSize;
  final double? opacity;
}

/// 行内覆盖标签的解析结果
class _AssOverride {
  const _AssOverride({
    this.alignment,
    this.pos,
    this.italic,
    this.bold,
    this.color,
    this.opacity,
    this.fontSize,
    this.rotateZ,
  });
  final int? alignment;
  final Offset? pos;
  final bool? italic;
  final bool? bold;
  final Color? color;
  final double? opacity;
  final double? fontSize;

  /// `\frz`/`\fr`：绕 Z 轴旋转，单位度（负值逆时针）。跟 `\i1` 斜体不是一回事。
  final double? rotateZ;
}

class _ParsedText {
  const _ParsedText(this.runs, this.override);

  final List<_Run> runs;
  final _AssOverride override;

  static _ParsedText parse(String raw, AssStyle base, double fallbackFontSize) {
    final List<_Run> runs = <_Run>[];
    int? an;
    Offset? pos;
    bool? italic;
    bool? bold;
    Color? color;
    double? opacity;
    double? fontSize;
    double? rotateZ;

    final RegExp tagRe = RegExp(r'\{([^}]*)\}');
    int cursor = 0;
    void emit(String text) {
      if (text.isEmpty) return;
      final String normalised =
          text.replaceAll(r'\N', '\n').replaceAll(r'\n', '\n');
      runs.add(_Run(
        normalised,
        color: color,
        italic: italic,
        bold: bold,
        fontSize: fontSize,
        opacity: opacity,
      ));
    }

    for (final RegExpMatch m in tagRe.allMatches(raw)) {
      emit(raw.substring(cursor, m.start));
      cursor = m.end;
      for (final String tag in _splitTags(m.group(1) ?? '')) {
        final String t = tag.trim();
        if (t.isEmpty) continue;
        if (t.startsWith(r'\an')) {
          final int? v = int.tryParse(t.substring(3));
          if (v != null && v >= 1 && v <= 9) an = v;
        } else if (t.startsWith(r'\pos(')) {
          final RegExpMatch? pm =
              RegExp(r'\\pos\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)').firstMatch(t);
          if (pm != null) {
            final double? x = double.tryParse(pm.group(1)!);
            final double? y = double.tryParse(pm.group(2)!);
            if (x != null && y != null) pos = Offset(x, y);
          }
        } else if (t == r'\i1') {
          italic = true;
        } else if (t == r'\i0') {
          italic = false;
        } else if (t == r'\b1') {
          bold = true;
        } else if (t == r'\b0') {
          bold = false;
        } else if (t.startsWith(r'\frz') || t.startsWith(r'\fr')) {
          // \frz-10 / \fr-10：文本起手的 `\fr` 是 `\frz` 的简写
          final int cut = t.startsWith(r'\frz') ? 4 : 3;
          rotateZ = double.tryParse(t.substring(cut));
        } else if (t.startsWith(r'\fs')) {
          fontSize = double.tryParse(t.substring(3));
        } else if (t.startsWith(r'\1c') || t.startsWith(r'\c')) {
          final int? rgb = _assColor(
            t.substring(t.startsWith(r'\1c') ? 3 : 2),
          );
          if (rgb != null) color = Color(0xFF000000 | rgb);
        } else if (t.startsWith(r'\alpha') ||
            t.startsWith(r'\1a') ||
            t.startsWith(r'\a')) {
          final String hex = t.replaceAll(RegExp(r'^\\[a-z0-9]*&?H?'), '');
          final int? a = int.tryParse(hex.replaceAll('&', ''), radix: 16);
          if (a != null) opacity = (1 - (a & 0xFF) / 255).clamp(0.0, 1.0);
        }
      }
    }
    emit(raw.substring(cursor));
    // 全是标签、没有正文时保留一行空文本，避免 Stack 里出现 0 高度节点
    if (runs.isEmpty) {
      runs.add(_Run(raw.replaceAll(tagRe, '')));
    }
    return _ParsedText(
      runs,
      _AssOverride(
        alignment: an,
        pos: pos,
        italic: italic,
        bold: bold,
        color: color,
        opacity: opacity,
        fontSize: fontSize,
        rotateZ: rotateZ,
      ),
    );
  }

  /// 一个 `{}` 里可能挤着多个标签：`\an8\b1\c&H00FFFF&`
  static List<String> _splitTags(String block) {
    final List<String> out = <String>[];
    int start = 0;
    for (int i = 1; i < block.length; i++) {
      if (block[i] == r'\' && block[i - 1] != r'\') {
        out.add(block.substring(start, i));
        start = i;
      }
    }
    out.add(block.substring(start));
    return out;
  }

  static int? _assColor(String raw) {
    String v = raw.replaceAll('&', '').replaceAll('H', '').replaceAll('h', '');
    if (v.isEmpty) return null;
    if (v.length > 6) v = v.substring(v.length - 6);
    if (v.length < 6) return null;
    final int bgr = int.tryParse(v, radix: 16) ?? 0;
    final int b = (bgr >> 16) & 0xFF;
    final int g = (bgr >> 8) & 0xFF;
    final int r = bgr & 0xFF;
    return (r << 16) | (g << 8) | b;
  }
}
