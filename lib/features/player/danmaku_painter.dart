import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/room_message.dart';
import '../../theme/app_colors.dart';

/// 弹幕层缓存：`ui.Paragraph` 的排版是弹幕最贵的一步（04 §11.1 第 3 条铁律），
/// 所以这里跨帧复用，命中率目标 > 95%。
///
/// key 用 `text|size|color|bold`（同一句话换个轨道还是同一份排版）；
/// 上限 300 条，超了按 LRU 丢最久没用的那条。
class DanmakuParagraphCache {
  DanmakuParagraphCache({this.capacity = 300});

  final int capacity;
  final LinkedHashMap<String, ui.Paragraph> _map =
      LinkedHashMap<String, ui.Paragraph>();

  int _hits = 0;
  int _misses = 0;

  int get length => _map.length;

  /// 命中率，仅测试与日志用
  double get hitRate {
    final int total = _hits + _misses;
    if (total == 0) return 0;
    return _hits / total;
  }

  @visibleForTesting
  int get hits => _hits;

  @visibleForTesting
  int get misses => _misses;

  void clear() {
    _map.clear();
    _hits = 0;
    _misses = 0;
  }

  /// 取（或建）一条弹幕的排版结果。
  ///
  /// [maxWidth] 是排版宽度上限（调用方传 `size.width * 1.2`）。它进 key：
  /// 同一句话在竖屏（360×1.2=432）和全屏（784×1.2≈941）下的换行/省略结果
  /// 不一样，复用同一份 Paragraph 会把「…」的位置算错。
  ui.Paragraph get({
    required String text,
    required double fontSize,
    required int color,
    required bool bold,
    required double maxWidth,
  }) {
    final String key = '$text|${fontSize.toStringAsFixed(2)}|$color|'
        '${bold ? 'b' : ''}|${maxWidth.toStringAsFixed(1)}';
    final ui.Paragraph? hit = _map.remove(key);
    if (hit != null) {
      _hits++;
      _map[key] = hit; // 重新插到队尾 = 最近用过
      return hit;
    }
    _misses++;
    final ui.Paragraph p = _build(
      text: text,
      fontSize: fontSize,
      color: color,
      bold: bold,
      maxWidth: maxWidth,
    );
    _map[key] = p;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
    return p;
  }

  ui.Paragraph _build({
    required String text,
    required double fontSize,
    required int color,
    required bool bold,
    required double maxWidth,
  }) {
    final ui.ParagraphBuilder pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: fontSize,
        maxLines: 1,
        // 超长文本以「…」收尾，而不是硬切在第 N 个字（04 §11.3 的观感要求）。
        // 配合下面 layout 的宽度上限（约一屏宽）：超过这个宽度的文本自动省略。
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          // RoomDanmaku.color 是裸 RGB（帧里传 16777215 = 0xFFFFFF = 白），
          // 不是 ARGB。Color(int) 按 ARGB 解 → 0x00FFFFFF → alpha=0 →
          // 填充完全透明，屏幕上只剩四向黑阴影围出的轮廓，小字号时看起来是黑字。
          // 补上不透明 alpha。
          color: Color(0xFF000000 | (color & 0xFFFFFF)),
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          // 描边：四向 blurRadius 0 的黑阴影，等效 1px 硬描边。
          // 原来用 blurRadius 2 的软阴影，压在亮蓝/粉底上会糊成半透明灰、
          // 和背景混在一起（dm_portrait 里「满屏弹幕 23」压在 BBB logo 上读不出）。
          // 仍然只是一个 Paragraph、一次 drawParagraph，绘制次数不变。
          shadows: const <Shadow>[
            Shadow(offset: Offset(-1, 0), color: Color(0xFF000000)),
            Shadow(offset: Offset(1, 0), color: Color(0xFF000000)),
            Shadow(offset: Offset(0, -1), color: Color(0xFF000000)),
            Shadow(offset: Offset(0, 1), color: Color(0xFF000000)),
          ],
        ),
      )
      ..addText(text);
    return pb.build()
      // 宽度上限约一屏宽（调用方按 size.width * 1.2 算，竖屏 360 → 432）：
      // 超出的部分交给上面的 ellipsis 画「…」；不能用无限宽，
      // 否则 maxLines/ellipsis 的省略永远不会触发，一条弹幕会拖出 3 屏。
      ..layout(ui.ParagraphConstraints(width: maxWidth));
  }
}

/// 全局共用一份：切换页面、切全屏都不该把已经排好的版丢光。
final DanmakuParagraphCache kDanmakuParagraphCache = DanmakuParagraphCache();

/// 弹幕渲染层（04 §11）。
///
/// 三条铁律：
/// 1. 绝不一条弹幕一个 Widget —— 全部在这一个 CustomPainter 里画；
/// 2. 外层由 `DanmakuOverlay` 包 RepaintBoundary；
/// 3. 排版走 [kDanmakuParagraphCache]（带 LRU），每帧只算坐标不算排版。
class DanmakuPainter extends CustomPainter {
  DanmakuPainter({
    required this.items,
    required this.position,
    this.speed = 120,
    this.opacity = 0.85,
    this.fontSize = 15,
    required this.safeTop,
    required this.safeBottom,
    this.cache,
    this.likes = const <String, int>{},
  });

  /// 已按 pos 升序、已过滤掉不该出现的（重连/撤回后的残留由外部处理）
  final List<RoomDanmaku> items;

  /// 当前播放位置（相对视频）
  final Duration position;

  /// 用户档位：80 慢 / 120 中 / 180 快。
  /// 语义是「基准 8 秒的倍率来源」，不是像素每秒（04 §11.3 固定时间穿屏）。
  final double speed;

  /// 0.0–1.0，设置面板可调
  final double opacity;

  /// 基准字号（每条弹幕再乘自己的 size：0.8 / 1.0 / 1.2）
  final double fontSize;

  /// 安全区上沿（05 §②：视频高度的 21%）
  final double safeTop;

  /// 安全区下沿（视频高度的 61%）
  final double safeBottom;

  final DanmakuParagraphCache? cache;

  /// 弹幕点赞数（danmakuId → n）。只读，来自 RoomClient.danmakuLikes。
  final Map<String, int> likes;

  /// 本帧画过的弹幕命中框（id + 屏幕坐标），长按命中检测读它。
  /// 每帧开头清空，paint 末尾填满 —— 结构是记录类型，不会分配 Paragraph。
  final List<({String id, Rect rect})> lastRects = <({String id, Rect rect})>[];

  /// 「+N」用的独立 TextPainter 缓存：不并进正文 Paragraph，
  /// 否则缓存 key 会随点赞数每帧变化，300 条 LRU 立刻全废。
  static final Map<String, TextPainter> _likePainters = <String, TextPainter>{};
  static const int _likePainterMax = 120;

  /// 绘制窗口左边界：一条弹幕从右边缘走到左边缘外面所需的时间 + 1 秒余量。
  ///
  /// 穿屏时间 = 屏宽 / 速度。竖屏 360 宽、速度 120 → 3 秒，加余量 = 4 秒。
  ///
  /// 历史：这里原本写死 8.0，出处是 04 §11.3「固定时间穿屏 8s」——
  /// 那条规则描述的是「一条弹幕在屏幕上停留不超过 8 秒」的**上限**，
  /// 而不是「出屏后还要继续画 8 秒」。屏宽 360、speed=120 时 3 秒就完全穿屏，
  /// 写 8 意味着出屏后还要白画 5 秒（画在屏幕左侧外面，被裁掉），
  /// 100 条压测时这部分是纯浪费。所以改成按实际参数算，1 秒余量
  /// 保证弹幕刚走到边缘（x 略小于 0、尾部还在屏内）时不会被提前剔掉。
  static double windowBehindFor(double width, double speed) {
    // 参数异常（宽或速度没测出来）时退回旧值 8 秒，宁可多画也不要整层空白
    if (speed <= 0 || width <= 0) return 8.0;
    return width / speed + 1.0;
  }

  static const double windowAhead = 0.5;

  /// 04 §11.3：所有弹幕都是 8 秒穿完（不是固定速度）。
  static const double baseCrossSeconds = 8.0;

  /// 档位 120 = 基准速度（8 秒），80 → 12 秒，180 → 5.33 秒。
  static const double baseSpeed = 120.0;

  /// 一条弹幕的穿屏秒数：8.0 × (120 / speed)。
  static double crossSecondsFor(double speed) =>
      speed <= 0 ? baseCrossSeconds : baseCrossSeconds * (baseSpeed / speed);

  /// 该条弹幕的实际移动速度 px/s = 总行程 / 穿屏秒数。
  /// 长弹幕（屏宽 + 440）比短弹幕快 —— 这正是固定时间方案的特征。
  static double travelSpeedFor({
    required double width,
    required double textWidth,
    required double speed,
  }) =>
      (width + textWidth) / crossSecondsFor(speed);

  /// 固定时间穿屏的横坐标：t=0 在右边缘（x=屏宽），t=crossSec 时整条出左边界
  /// （x = -textWidth）。同一个 id 从 x=屏宽 到 x=-w 恰好 crossSec 秒。
  static double xFor({
    required double width,
    required double elapsed,
    required double textWidth,
    required double speed,
  }) =>
      width -
      elapsed *
          travelSpeedFor(width: width, textWidth: textWidth, speed: speed);

  /// debug 采样节流：每个弹幕 id 每 250ms 打一行 trace（验收用）。
  static final Map<String, int> _traceStep = <String, int>{};

  /// 轨道数上限（04 §11.4 写的是 16 等分）
  static const int laneCount = 16;

  /// 实际可用轨道数：安全区只有视频高度的 40%，竖屏 202 高时只有 81px；
  /// 硬切 16 条的话每条 5px，15 号字必然糊成一片。所以按字号定：
  /// 每条至少 1.5 倍字号高，上限仍是 16。
  static int lanesFor(double band, double fontSize) {
    if (band <= 0 || fontSize <= 0) return 1;
    final int n = (band / (fontSize * 1.5)).floor();
    return n < 1 ? 1 : (n > laneCount ? laneCount : n);
  }

  /// size 是倍数不是字号（room_message.dart:110 注释：0.8 / 1.0 / 1.2）。
  /// 对端若按别家习惯发字号（比如 15），15×15=225px 的字会把整条轨道吃掉，
  /// 还会让 (laneHeight - size2)/2 变成负数把 y 推到屏幕外。按 0.5-2.0 封顶。
  static double scaleFor(double size) =>
      size <= 0 ? 1.0 : size.clamp(0.5, 2.0).toDouble();

  /// 同轨两条之间的最小水平间隙，防「接龙」
  static const double laneGap = 40;

  DanmakuParagraphCache get _cache => cache ?? kDanmakuParagraphCache;

  double get _nowSec => position.inMilliseconds / 1000.0;

  /// 每帧耗时统计（验收要看「弹幕层帧时间 < 16ms」；gfxinfo 读不到
  /// media_kit 的纹理帧，所以这里自己量）
  static int _statFrames = 0;
  static int _statMaxUs = 0;
  static int _statSumUs = 0;
  static int _statSecond = -1;

  static void _stat(int us, int nowSec) {
    if (nowSec != _statSecond) {
      if (_statFrames > 0) {
        debugPrint('[YQK-DM] frame cost avg=${(_statSumUs / _statFrames / 1000).toStringAsFixed(2)}ms '
            'max=${(_statMaxUs / 1000).toStringAsFixed(2)}ms n=$_statFrames');
      }
      _statSecond = nowSec;
      _statFrames = 0;
      _statMaxUs = 0;
      _statSumUs = 0;
    }
    _statFrames++;
    _statSumUs += us;
    if (us > _statMaxUs) _statMaxUs = us;
  }

  /// 该不该画这一条：只画 [position-windowBehind, position+0.5s] 之内。
  /// windowBehind 见 [windowBehindFor]：穿屏时间 + 1 秒余量（不再是写死的 8s）。
  /// 不传 behind 时按默认参数（360 宽、120 速度 → 4 秒）算，方便单测。
  @visibleForTesting
  static bool inWindow(double pos, double now, [double? behind]) {
    final double b = behind ?? windowBehindFor(360, 120);
    return pos <= now + windowAhead && pos >= now - b;
  }

  /// 长按命中：从最后画的（最上层）往下找，返回命中的弹幕 id；没命中返回 null。
  /// 抽成静态函数是为了单测能直接验，不用起一个 Overlay。
  static String? hitTestRects(List<({String id, Rect rect})> boxes, Offset p) {
    for (int i = boxes.length - 1; i >= 0; i--) {
      if (boxes[i].rect.contains(p)) return boxes[i].id;
    }
    return null;
  }

  /// 「+N」用的小 TextPainter：正文的 0.8 倍字号、主题蓝、四向黑描边。
  /// 单独缓存（按 文本|字号），正文 Paragraph 的 key 完全不受影响。
  static TextPainter _likePainter(String text, double fontSize) {
    final String key = '$text|${fontSize.toStringAsFixed(1)}';
    final TextPainter? hit = _likePainters[key];
    if (hit != null) return hit;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          shadows: const <Shadow>[
            Shadow(offset: Offset(-1, 0), color: Color(0xFF000000)),
            Shadow(offset: Offset(1, 0), color: Color(0xFF000000)),
            Shadow(offset: Offset(0, -1), color: Color(0xFF000000)),
            Shadow(offset: Offset(0, 1), color: Color(0xFF000000)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (_likePainters.length >= _likePainterMax) _likePainters.clear();
    _likePainters[key] = tp;
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Stopwatch sw = Stopwatch()..start();
    if (items.isEmpty || size.width <= 0 || size.height <= 0) {
      sw.stop();
      return;
    }
    final double now = _nowSec;
    // 弹幕长度上限约一屏宽（留 20% 余量给「…」和边缘）。
    // 04 §11.3「固定时间 8 秒」的前提是长度可控；允许 3 屏长的话，
    // 8 秒穿完要 180px/s，根本读不完。超过一屏就省略，与 B 站一致。
    // 不能写成固定 1080/720：盒子 360、手机 411、全屏 784 都要各自自适应。
    final double maxTextWidth = size.width * 1.2;
    // windowBehindFor 仍是「一条普通宽度弹幕的可见时长」的参考值（单测 inWindow 用它），
    // paint 里不再拿它做剔除以假长文本被提前裁掉，见循环内的注释。
    final double laneTop = safeTop > 0 ? safeTop : size.height * 0.21;
    final double laneBottom = safeBottom > 0 ? safeBottom : size.height * 0.61;
    final int lanes = lanesFor(laneBottom - laneTop, fontSize);
    final double laneHeight = (laneBottom - laneTop) / lanes;
    if (laneHeight <= 1) return;

    // 每个轨道里最后一条弹幕的右边缘（-inf = 空轨）
    final List<double> laneRight =
        List<double>.filled(lanes, double.negativeInfinity);

    canvas.save();
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    int drawn = 0;
    int skipped = 0;
    lastRects.clear();
    for (final RoomDanmaku d in items) {
      if (d.pos > now + windowAhead) break; // 已排序：后面的只会更晚
      // 这里不做时间窗口粗筛：窗口是按「一条弹幕约一屏宽」估的，
      // 90 字的长弹幕比窗口cover的宽度还长，会被提前剔掉（实测尾部还没露出就没了）。
      // 真正的剔除交给下面的几何判断：x + 文本宽 < 0 才算整条滚出左边。
      final double elapsed = now - d.pos;
      final double scale = scaleFor(d.size);
      final double size2 = fontSize * scale;
      final ui.Paragraph p = _cache.get(
        text: d.text,
        fontSize: size2,
        color: d.color,
        bold: d.bold,
        maxWidth: maxTextWidth,
      );
      // w 必须早于 x：固定时间穿屏的总行程 = 屏宽 + 自身宽度。
      final double w = p.longestLine;
      // 04 §11.3：固定时间穿屏，不是固定速度。
      // 总行程 = 屏宽 + 自身宽度，8 秒走完 —— 长弹幕移动快、短弹幕移动慢，
      // 不会出现「长弹幕挡屏 12 秒」这种固定速度方案的固有问题。
      final double x = xFor(
        width: size.width,
        elapsed: elapsed,
        textWidth: w,
        speed: speed,
      );
      if (kDebugMode && d.id.startsWith('dbg_')) {
        final int step = (elapsed * 4).floor();
        if (_traceStep[d.id] != step) {
          _traceStep[d.id] = step;
          debugPrint('[YQK-DM] trace id=${d.id} t=${elapsed.toStringAsFixed(2)} '
              'x=${x.toStringAsFixed(1)} w=${w.toStringAsFixed(1)} '
              'v=${travelSpeedFor(width: size.width, textWidth: w, speed: speed).toStringAsFixed(1)} '
              'cross=${crossSecondsFor(speed).toStringAsFixed(2)}');
        }
        if (_traceStep.length > 200) _traceStep.clear();
      }
      if (x + w < 0) continue; // 已经整条滚出左边界
      final int lane = allocateLane(
        id: d.id,
        x: x,
        width: w,
        laneRight: laneRight,
      );
      // 每轨文字顶端对齐，不在轨内垂直居中。
      //
      // 规格验收口径是「第 0 轨 y == laneTop == 21% × h」（05 §弹幕安全区）。
      // 居中版本 y = laneTop + (laneHeight - size)/2，203 高的视频上多出 6 逻辑
      // = 18 物理，量出来永远是 24% 而不是 21%，和规格对不上；而且多出的 6 逻辑
      // 正好把第 0 轨推进标题栏的渐变遮罩里。laneHeight / 轨数 / laneGap 都不动。
      final double y = laneTop + lane * laneHeight;
      canvas.drawParagraph(p, Offset(x, y));
      // 点赞数画在正文右侧 +4px：独立 TextPainter，绝不并进正文 Paragraph
      // （并进去缓存 key 会随点赞数每帧变，300 条 LRU 立刻全废）。
      final int likeN = likes[d.id] ?? 0;
      double boxW = w;
      if (likeN > 0) {
        final TextPainter tp = _likePainter('+$likeN', size2 * 0.8);
        final double lx = x + w + 4;
        tp.paint(canvas, Offset(lx, y + (size2 - tp.height) / 2));
        // 命中框含「+N」，长按数字也算点到这条弹幕
        boxW = w + 4 + tp.width;
      }
      lastRects.add((id: d.id, rect: Rect.fromLTWH(x, y, boxW, size2)));
      drawn++;
    }
    canvas.restore();
    canvas.restore();
    sw.stop();
    _stat(sw.elapsedMicroseconds, now.floor());
    if ((_nowSec * 10).round() % 10 == 0) {
      debugPrint('[YQK-DM] paint size=${size.width.toStringAsFixed(0)}x'
          '${size.height.toStringAsFixed(0)} items=${items.length} drawn=$drawn '
          'skip=$skipped now=${_nowSec.toStringAsFixed(1)} lanes=$lanes '
          'laneTop=${laneTop.toStringAsFixed(1)} '
          'laneBottom=${laneBottom.toStringAsFixed(1)} '
          'laneH=${laneHeight.toStringAsFixed(2)} '
          'lane0=${laneTop.toStringAsFixed(1)}');
    }
  }

  /// 轨道分配：先按 id 哈希取一条，被占就往下挪，全满返回最后一轨
  /// （不是丢弃 —— 房间弹幕量小，宁可叠一下也别让人看不到自己的话）。
  @visibleForTesting
  static int allocateLane({
    required String id,
    required double x,
    required double width,
    required List<double> laneRight,
  }) {
    if (laneRight.isEmpty) return 0;
    final int wanted = id.hashCode.abs() % laneRight.length;
    for (int i = 0; i < laneRight.length; i++) {
      final int lane = (wanted + i) % laneRight.length;
      final double right = laneRight[lane];
      if (right == double.negativeInfinity || right + laneGap <= x) {
        laneRight[lane] = x + width;
        return lane;
      }
    }
    final int fallback = wanted % laneRight.length;
    laneRight[fallback] = x + width;
    return fallback;
  }

  @override
  bool shouldRepaint(covariant DanmakuPainter old) =>
      old.position != position ||
      old.items.length != items.length ||
      old.speed != speed ||
      old.opacity != opacity ||
      old.fontSize != fontSize ||
      old.likes != likes;
}
