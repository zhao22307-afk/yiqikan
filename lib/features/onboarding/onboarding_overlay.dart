import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/prefs.dart';
import '../../theme/app_colors.dart';

/// 一步引导：高亮 [key] 对应的控件，在它旁边放气泡。
class OnboardingStep {
  const OnboardingStep({
    required this.key,
    required this.title,
    required this.desc,
    this.fraction,
    // 挖洞比控件外扩 2 逻辑像素（1080 宽屏约 6 物理像素），
    // 保证遮罩不压住控件本体、又能看出高亮框的边。
    this.holePadding = 2,
  });

  /// 被高亮控件的 GlobalKey（必须已经挂到 widget 树上）
  final GlobalKey key;
  final String title;
  final String desc;

  /// 目标控件只是「一片区域」时再切一刀，比如底部导航只高亮右半边：
  /// `Rect.fromLTRB(0.5, 0, 1, 1)` = 取目标矩形的右半。
  final Rect? fraction;

  /// 挖洞比控件外扩几像素（视觉上留一点呼吸，报告里 C-V5 的误差按这个算）
  final double holePadding;
}

/// 跨页面触发引导：设置页把 `onboardingDone` 清掉后 `replay()`，
/// 首页监听到就会立刻再弹一次（不用重启 App）。
class OnboardingGate {
  OnboardingGate._();
  static final ValueNotifier<int> request = ValueNotifier<int>(0);
  static void replay() => request.value = request.value + 1;
}

/// G5 首启引导：自绘遮罩 + 挖洞高亮，不引 tutorial_coach_mark。
///
/// 用法：首页首帧后 `if (!prefs.getBool(onboardingDone))` 就
/// `Navigator.push(OnboardingOverlay(...))`；三步走完 / 跳过都写 true。
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({
    super.key,
    required this.steps,
    this.onFinish,
  });

  final List<OnboardingStep> steps;

  /// 结束回调（完成或跳过都调，参数为是否走完）
  final void Function(bool completed)? onFinish;

  /// 当前正在显示的引导（防止重复弹两份）
  static bool get visible => _routeOpen;
  static bool _routeOpen = false;

  /// 写盘 + 打日志的统一出口
  static Future<void> markDone(Prefs prefs, {required String why}) async {
    await prefs.setBool(PrefKeys.onboardingDone, true);
    debugPrint('[YQK-GUIDE] done=true why=$why');
  }

  static Future<void> show(
    BuildContext context, {
    required List<OnboardingStep> steps,
    required Prefs prefs,
  }) async {
    debugPrint('[YQK-GUIDE] show steps=${steps.length} open=$_routeOpen');
    if (_routeOpen) return;
    _routeOpen = true;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (BuildContext _, Animation<double> __, Animation<double> ___) =>
            OnboardingOverlay(
          steps: steps,
          onFinish: (bool completed) => unawaited(
            markDone(prefs, why: completed ? 'completed' : 'skipped'),
          ),
        ),
      ),
    );
    _routeOpen = false;
  }

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _i = 0;

  OnboardingStep get _step => widget.steps[_i];

  /// 目标控件在屏幕上的矩形（拿不到就返回 null，气泡退回居中）
  Rect? _targetRect(Size screen) {
    final BuildContext? ctx = _step.key.currentContext;
    if (ctx == null) return null;
    final RenderObject? ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    final Offset origin = ro.localToGlobal(Offset.zero);
    Rect r = origin & ro.size;
    final Rect? f = _step.fraction;
    if (f != null) {
      r = Rect.fromLTRB(
        r.left + r.width * f.left,
        r.top + r.height * f.top,
        r.left + r.width * f.right,
        r.top + r.height * f.bottom,
      );
    }
    final double p = _step.holePadding;
    final Rect out = Rect.fromLTRB(r.left - p, r.top - p, r.right + p, r.bottom + p);
    debugPrint('[YQK-GUIDE] step=${_i + 1} target='
        '${out.left.toStringAsFixed(1)},${out.top.toStringAsFixed(1)},'
        '${out.width.toStringAsFixed(1)},${out.height.toStringAsFixed(1)} '
        'screen=${screen.width.toStringAsFixed(0)}x${screen.height.toStringAsFixed(0)}');
    return out;
  }

  void _next() {
    if (_i + 1 >= widget.steps.length) {
      _finish(true);
    } else {
      setState(() => _i += 1);
      debugPrint('[YQK-GUIDE] next step=${_i + 1}');
    }
  }

  void _finish(bool completed) {
    debugPrint('[YQK-GUIDE] finish completed=$completed steps=${_i + 1}/'
        '${widget.steps.length}');
    widget.onFinish?.call(completed);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final Rect? target = _targetRect(screen);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: <Widget>[
          // 遮罩：整屏半透明，再用 difference 挖掉目标区域
          Positioned.fill(
            child: GestureDetector(
              // 点遮罩不关引导（避免误触跳过被高亮的控件）
              onTap: () {},
              child: CustomPaint(
                painter: _HolePainter(
                  hole: target,
                  color: const Color(0xCC000000),
                  radius: 12,
                ),
              ),
            ),
          ),
          if (target != null)
            // 被高亮的控件本身也要能点：放一块透明区域，让它透下去
            Positioned.fromRect(
              rect: target,
              child: const IgnorePointer(child: SizedBox.shrink()),
            ),
          _bubble(context, screen, target),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, Size screen, Rect? target) {
    const double bubbleW = 300;
    final double left = (screen.width - bubbleW) / 2;
    // 目标在上半屏 → 气泡放下面；否则放上面
    final bool below = target == null || target.center.dy < screen.height * 0.55;
    final double? top = target == null
        ? screen.height * 0.4
        : (below
            ? (target.bottom + 16).clamp(16.0, screen.height - 220)
            : (target.top - 200).clamp(16.0, screen.height - 220));

    return Positioned(
      left: left,
      top: top!,
      width: bubbleW,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _step.title,
                    style: AppText.title.copyWith(fontSize: 16),
                  ),
                ),
                Text(
                  '${_i + 1}/${widget.steps.length}',
                  style: AppText.sub.copyWith(color: AppColors.textDim),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_step.desc, style: AppText.body.copyWith(color: AppColors.textSub)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => _finish(false),
                  child: const Text('跳过'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _next,
                  child: Text(_i + 1 >= widget.steps.length ? '完成' : '下一步'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏半透明 + 圆角矩形挖洞
class _HolePainter extends CustomPainter {
  const _HolePainter({required this.hole, required this.color, this.radius = 12});

  final Rect? hole;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Path full = Path()..addRect(Offset.zero & size);
    final Rect? h = hole;
    if (h == null) {
      canvas.drawPath(full, Paint()..color = color);
      return;
    }
    final Path holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(h, Radius.circular(radius)));
    final Path mask = Path.combine(PathOperation.difference, full, holePath);
    canvas.drawPath(mask, Paint()..color = color);
    // 高亮描边，让洞的位置一眼可见
    canvas.drawRRect(
      RRect.fromRectAndRadius(h, Radius.circular(radius)),
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HolePainter old) =>
      old.hole != hole || old.color != color || old.radius != radius;
}
