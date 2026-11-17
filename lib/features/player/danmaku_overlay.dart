import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/danmaku_filter.dart';
import '../../domain/entities/room_message.dart';
import '../../platform/room/room_client.dart';
import '../player/player_controller.dart';
import 'danmaku_painter.dart';

/// 弹幕显示设置（本地偏好，不联网不上报）。
///
/// 存五个 key：`danmaku_visible` / `danmaku_opacity` / `danmaku_speed` / `danmaku_font`
/// / `danmaku_send`，下次进房由 [DanmakuSettings.load] 恢复。
///
/// 注意 [visible] 与 [sendEnabled] 是两件事，别合并：
/// - [visible] = 看不看得到弹幕层（纯本地显示，影响渲染）；
/// - [sendEnabled] = 发聊天时要不要顺带发一条弹幕（影响协议，别人也收得到）。
///   关掉它只影响自己发不发，别人的弹幕照常显示。
@immutable
class DanmakuSettings {
  const DanmakuSettings({
    this.visible = true,
    this.opacity = 0.85,
    this.speed = 120,
    this.fontSize = 15,
    this.sendEnabled = true,
    this.filterEnabled = true,
    this.filterOptions = const FilterOptions(),
  });

  static const String kVisible = 'danmaku_visible';
  static const String kOpacity = 'danmaku_opacity';
  static const String kSpeed = 'danmaku_speed';
  static const String kFont = 'danmaku_font';
  static const String kSend = 'danmaku_send';
  static const String kFilter = 'danmaku_filter';
  static const String kFilterOpts = 'danmaku_filter_opts';

  final bool visible;

  /// 发聊天时是否同时发一条弹幕（默认开）
  final bool sendEnabled;

  /// H3：收到的弹幕要不要过一遍垃圾/剧透/重复过滤（默认开）。
  /// 自己发的永远不过滤 —— 见 [DanmakuOverlay._onItems]。
  final bool filterEnabled;

  /// H3 五条规则的细开关
  final FilterOptions filterOptions;

  /// 0.3 / 0.5 / 0.85
  final double opacity;

  /// 80 慢 / 120 中 / 180 快（像素每秒）
  final double speed;

  /// 13 小 / 15 中 / 18 大
  final double fontSize;

  DanmakuSettings copyWith({
    bool? visible,
    double? opacity,
    double? speed,
    double? fontSize,
    bool? sendEnabled,
    bool? filterEnabled,
    FilterOptions? filterOptions,
  }) {
    return DanmakuSettings(
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      fontSize: fontSize ?? this.fontSize,
      sendEnabled: sendEnabled ?? this.sendEnabled,
      filterEnabled: filterEnabled ?? this.filterEnabled,
      filterOptions: filterOptions ?? this.filterOptions,
    );
  }

  static Future<DanmakuSettings> load() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return DanmakuSettings(
        visible: p.getBool(kVisible) ?? true,
        opacity: p.getDouble(kOpacity) ?? 0.85,
        speed: p.getDouble(kSpeed) ?? 120,
        fontSize: p.getDouble(kFont) ?? 15,
        sendEnabled: p.getBool(kSend) ?? true,
        filterEnabled: p.getBool(kFilter) ?? true,
        filterOptions: FilterOptions.fromJson(
          p.getString(kFilterOpts) == null
              ? null
              : jsonDecode(p.getString(kFilterOpts)!),
        ),
      );
    } catch (_) {
      return const DanmakuSettings();
    }
  }

  Future<void> save() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(kVisible, visible);
      await p.setDouble(kOpacity, opacity);
      await p.setDouble(kSpeed, speed);
      await p.setDouble(kFont, fontSize);
      await p.setBool(kSend, sendEnabled);
      await p.setBool(kFilter, filterEnabled);
      await p.setString(kFilterOpts, jsonEncode(filterOptions.toJson()));
    } catch (_) {}
  }
}

/// 弹幕渲染层（只负责驱动重绘 + 隔离重绘 + 不吃点击）。
///
/// - 50ms 一跳（20fps）：弹幕不需要 60fps，省电也省帧；
/// - 只在「有弹幕 && 在播放 && 开着」时跑，暂停/隐藏就停 Timer；
/// - `IgnorePointer` 让点击穿到视频手势层，`RepaintBoundary` 让视频每帧变化
///   不再拖着弹幕一起重绘（04 §11.1 第 2 条铁律）。
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    this.danmakus,
    this.settings = const DanmakuSettings(),
    this.likes = const <String, int>{},
    this.onDanmakuLike,
    this.onHitBoxes,
  });

  final PlayerController controller;
  final ValueListenable<List<RoomDanmaku>>? danmakus;
  final DanmakuSettings settings;

  /// 点赞数（danmakuId → n），画在每条弹幕右侧
  final Map<String, int> likes;

  /// 长按命中某条弹幕时回调（player_page 负责发帧 + 乐观 +1）
  final ValueChanged<String>? onDanmakuLike;

  /// 每帧把命中框交给外面（player_page 的长按手势层拿它做命中检测）。
  ///
  /// 为什么要外抛：视频手势层 `_gestureLayer` 在 Stack 里位于弹幕层**之上**且是
  /// opaque，所以这层自己的 GestureDetector 在主页面永远收不到事件；
  /// 真正的事件源是那条 opaque 层，它需要读这份矩形去判「这一下按在弹幕上吗」。
  final ValueChanged<List<({String id, Rect rect})>>? onHitBoxes;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  static const int _tickMs = 50;

  /// 裁剪窗口：只保留「当前播放位置往前 12 秒」的弹幕（12 = 8 秒穿屏 + 4 秒余量）。
  /// 未来弹幕（pos > _pos）一条都不裁 —— 房间回放会提前把还没到的弹幕发过来。
  static const Duration _keepBehind = Duration(seconds: 12);

  Timer? _timer;

  /// 暂停时的「恢复了吗」探针（400ms 一次，比 20fps 省得多）
  Timer? _watch;
  List<RoomDanmaku> _items = const <RoomDanmaku>[];
  Duration _pos = Duration.zero;

  /// 50ms tick 的计数，每 40 跳触发一次重裁（seek 之后列表不变也要裁）
  int _ticks = 0;

  /// 上一次打日志的 layout 尺寸（'w x h'），尺寸不变就不重复打
  String? _loggedSize;

  /// 当前帧的 painter（每次 build 新建）。长按命中读它的 lastRects。
  DanmakuPainter? _painter;

  /// 上一帧画过的弹幕命中框（供长按查询；纯本地几何，不做 Widget）
  List<({String id, Rect rect})> _hitBoxes = const <({String id, Rect rect})>[];

  /// 长按：命中哪条就回调哪条。没命中打一行 miss（验收要看这一步没误触）。
  void _onLongPressStart(LongPressStartDetails details) {
    final Offset p = details.localPosition;
    final List<({String id, Rect rect})> boxes =
        _painter?.lastRects ?? _hitBoxes;
    final String? hit = DanmakuPainter.hitTestRects(boxes, p);
    if (hit != null) {
      debugPrint('[YQK-DM] like hit id=$hit '
          'x=${p.dx.toStringAsFixed(1)} y=${p.dy.toStringAsFixed(1)}');
      widget.onDanmakuLike?.call(hit);
      return;
    }
    debugPrint('[YQK-DM] like miss x=${p.dx.toStringAsFixed(1)} '
        'y=${p.dy.toStringAsFixed(1)}');
  }

  @override
  void initState() {
    super.initState();
    widget.danmakus?.addListener(_onItems);
    widget.controller.addListener(_onController);
    _onItems();
    _pos = widget.controller.position;
    // 挂载时 playing 可能已经是 true（那一跳通知早就过去了）：主动同步一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTimer();
    });
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (old.danmakus != widget.danmakus) {
      old.danmakus?.removeListener(_onItems);
      widget.danmakus?.addListener(_onItems);
      _onItems();
    }
    _syncTimer();
  }

  @override
  void dispose() {
    _stopAll();
    widget.danmakus?.removeListener(_onItems);
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onItems() {
    final List<RoomDanmaku> all =
        widget.danmakus?.value ?? const <RoomDanmaku>[];
    // H3：只过滤「别人发的」。自己发的一条都不挡 —— 否则会出现
    // 「我明明发出去了，屏幕上没有」，用户会以为发送失败。
    final String? me = RoomClient.current?.memberId;
    final bool on = widget.settings.filterEnabled;
    final List<RoomDanmaku> kept = <RoomDanmaku>[];
    final List<String> recent = <String>[];
    final int floorSec = (_pos.inMilliseconds / 1000.0 - 12).floor();
    for (final RoomDanmaku d in all) {
      if (d.pos >= floorSec) {
        recent.add(d.text);
        if (recent.length > 20) recent.removeAt(0);
      }
      if (!on || (me != null && d.from == me)) {
        kept.add(d);
        continue;
      }
      final FilterResult r = DanmakuFilter.check(
        d.text,
        recent.sublist(0, recent.length > 1 ? recent.length - 1 : 0),
        options: widget.settings.filterOptions,
      );
      if (!r.blocked) {
        kept.add(d);
      } else if (kDebugMode) {
        debugPrint('[YQK-DM] filter id=${d.id} reason=${r.reason.name} '
            'hit=${r.hit ?? ''} text=${d.text}');
      }
    }
    // painter 里靠「pos 升序 → 超过窗口就 break」，所以这里只排一次序；
    // 排序顺带把过期的挪到表头，_prune 只需要从头上砍。
    final List<RoomDanmaku> next = kept
      ..sort((RoomDanmaku a, RoomDanmaku b) => a.pos.compareTo(b.pos));
    _items = next;
    final int pruned = _prune();
    debugPrint('[YQK-DM] items=${_items.length} pruned=$pruned '
        'playing=${widget.controller.playing} pos=${_pos.inMilliseconds / 1000.0}'
        '${all.length == next.length ? '' : ' filtered=${all.length - next.length}'}');
    _syncTimer();
  }

  /// 丢掉「已经过去超过 [_keepBehind]」的弹幕，返回裁掉的条数。
  ///
  /// `_items` 按 pos 升序，所以只需从表头砍连续的一段：第一个
  /// `pos >= _pos - 12s` 之后的所有条目原样保留，含**全部未来弹幕**。
  /// 不裁未来是有意的：房间回放会提前收到还没播到的弹幕。
  int _prune({bool log = false}) {
    final int before = _items.length;
    if (before == 0) return 0;
    // RoomDanmaku.pos 是「秒」的 double，_pos 是 Duration：统一换成秒再比
    final double floorSec =
        _pos.inMilliseconds / 1000.0 - _keepBehind.inMilliseconds / 1000.0;
    // O(1) 快速路径：表头那条还没过期，整表都不用动
    if (_items.first.pos >= floorSec) return 0;
    final List<RoomDanmaku> kept = <RoomDanmaku>[
      for (final RoomDanmaku d in _items)
        if (d.pos >= floorSec) d,
    ];
    _items = kept;
    final int pruned = before - kept.length;
    if (log && pruned > 0) {
      debugPrint('[YQK-DM] prune $before -> ${_items.length} '
          'pos=${_pos.inMilliseconds / 1000.0}');
    }
    return pruned;
  }

  void _onController() {
    // 播放/暂停、切集这类低频事件：用来决定 Timer 起停
    _syncTimer();
    if (!widget.controller.playing) {
      // 暂停时把位置定住（否则恢复瞬间会跳一段）
      if (mounted) setState(() => _pos = widget.controller.position);
    }
  }

  void _syncTimer() {
    final bool wantRun = widget.settings.visible && _items.isNotEmpty;
    if (!wantRun) {
      _stopAll();
      if (mounted) setState(() {});
      return;
    }
    if (widget.controller.playing) {
      _startFast();
    } else {
      // 暂停：停掉 20fps 的重绘，只留一个 400ms 的「恢复了吗」探针。
      // 不能只靠 ChangeNotifier —— 客人从 0 起播时 playing 可能在我们挂载
      // 之前就已经变成 true，那一跳通知永远不会再来（实测踩过：弹幕一条不画）。
      _timer?.cancel();
      _timer = null;
      _watch ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
        if (!mounted) return;
        if (widget.controller.playing) {
          _watch?.cancel();
          _watch = null;
          _startFast();
        }
      });
    }
  }

  void _startFast() {
    _watch?.cancel();
    _watch = null;
    _timer ??= Timer.periodic(const Duration(milliseconds: _tickMs), (_) {
      if (!mounted) return;
      setState(() => _pos = widget.controller.position);
      // 每 40 跳（=2 秒）重裁一次：seek 之后弹幕列表本身没变，_onItems 不会
      // 再触发，只有靠这里把「跳过去之后已经过期」的那批从表里去掉。
      if (++_ticks % 40 == 0) {
        _prune(log: true);
        // 裁空了就把 50ms 的 tick 停掉（I-23）：没人要从帧里画东西，
        // 还每秒 20 次 setState 纯属白烧电；下一条弹幕进来 _onItems 会再启动。
        if (_items.isEmpty) _syncTimer();
      }
    });
    if (mounted) setState(() => _pos = widget.controller.position);
  }

  void _stopAll() {
    _timer?.cancel();
    _timer = null;
    _watch?.cancel();
    _watch = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.visible) return const SizedBox.shrink();
    return GestureDetector(
      // 竖屏下 _gestureLayer（opaque）压在弹幕层之上，本层事件永远收不到；
      // 命中实际走 player_page._tryLikeAt 委派。保留本层只为将来全屏布局。
      // translucent 是关键：单击（播放/暂停）照旧穿透到下面的视频手势层，
      // 只有长按被这层吃掉。别改成 opaque，那会把 tap 全抢走。
      behavior: HitTestBehavior.translucent,
      onLongPressStart: _onLongPressStart,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints cons) {
            final double h = cons.maxHeight;
            final double w = cons.maxWidth;
            // 只在尺寸变化时打，避免每帧刷屏：排查「弹幕偏上」时要知道
            // 这里拿到的到底是不是视频区高度（203 = 360/16*9），
            // 以及 safeTop 是不是 203×0.21 = 42.6。
            if (_loggedSize != '${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)}') {
              _loggedSize = '${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)}';
              debugPrint('[YQK-DM] layout h=${h.toStringAsFixed(1)} '
                  'w=${w.toStringAsFixed(1)} safeTop=${(h * 0.21).toStringAsFixed(1)} '
                  'safeBottom=${(h * 0.61).toStringAsFixed(1)}');
            }
            final DanmakuPainter painter = DanmakuPainter(
              items: _items,
              position: _pos,
              speed: widget.settings.speed,
              opacity: widget.settings.opacity,
              fontSize: widget.settings.fontSize,
              safeTop: h * 0.21,
              safeBottom: h * 0.61,
              likes: widget.likes,
            );
            _painter = painter;
            // 每帧同步命中框：直接持有 painter 那份 list 的引用（同一帧里 paint
            // 会就地 clear + 填满），不做拷贝，也不 setState —— 长按只读，不驱动 UI。
            _hitBoxes = painter.lastRects;
            widget.onHitBoxes?.call(painter.lastRects);
            return CustomPaint(
              size: Size(cons.maxWidth, h),
              painter: painter,
            );
          },
        ),
      ),
    );
  }
}
