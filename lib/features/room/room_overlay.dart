import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../platform/room/room_snapshot.dart';

/// 三个浮层各自定位、各自贴边（不再用一个 Column 从视频顶排到中间，
/// 那样 86 逻辑高会把 202.5 高的画面盖掉一大块 —— 见 room1.png）。
/// 每个都返回 Positioned，直接放进播放页的 Stack。
///
/// 只读快照：数据源是 `ValueListenable<RoomSnapshot?>`，写操作一律交给调用方。

/// 浮层落位：默认按 Positioned 贴在视频里；
/// `embedded: true` 时改成普通流式布局，供播放页把它们排在视频**下面**
/// （屏幕小的时候浮层压在画面上会跟播放控制条打架，见 L1 验收）。
Widget _slot({
  required bool embedded,
  required Widget child,
  double? top,
  double? bottom,
}) {
  if (embedded) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: child,
    );
  }
  return Positioned(left: 10, right: 10, top: top, bottom: bottom, child: child);
}


/// 成员条：贴视频顶，可点击收起成「N 人在看」小胶囊。
/// 房主长按成员 → 弹底部菜单（禁言 / 解除禁言 / 移出房间）；普通人长按没反应。
class RoomMemberBar extends StatefulWidget {
  const RoomMemberBar({
    super.key,
    required this.snapshot,
    this.memberId,
    this.onMute,
    this.onKick,
    this.embedded = false,
    this.voiceIds = const <String>{},
  });

  final ValueListenable<RoomSnapshot?> snapshot;

  /// 我自己的 memberId（判断我是不是房主、别把菜单开在自己头上）
  final String? memberId;

  /// 禁言 / 解除禁言：(memberId, muted)
  final void Function(String memberId, bool muted)? onMute;

  /// 移出房间：memberId
  final ValueChanged<String>? onKick;

  /// true = 排在视频下面（普通 Column 子项），false = 浮在视频里
  final bool embedded;

  /// 已在语音里的成员 id：chip 上用 🎤 标出来。
  /// 传集合而不是整个 VoiceState，是因为成员条只关心「谁在语音里」，
  /// 别的字段（满员、speaking）跟这一行没关系，传进来只会让它无谓重建。
  final Set<String> voiceIds;

  @override
  State<RoomMemberBar> createState() => _RoomMemberBarState();
}

class _RoomMemberBarState extends State<RoomMemberBar> {
  bool collapsed = false;

  @override
  Widget build(BuildContext context) {
    return _slot(
      embedded: widget.embedded,
      top: 8,
      child: ValueListenableBuilder<RoomSnapshot?>(
        valueListenable: widget.snapshot,
        builder: (BuildContext context, RoomSnapshot? snap, Widget? _) {
          if (snap == null) return const SizedBox.shrink();
          // 只列在线成员：离线历史成员留着会让 chip 数量与「N 人在看」对不上
          final List<RoomMember> live =
              snap.members.where((RoomMember m) => m.online).toList();
          if (live.isEmpty) return const SizedBox.shrink();
          final String meId = widget.memberId ?? '';
          // 固定位：自己优先，其次房主，再次第一个（微信群里那套）
          int pin = meId.isEmpty ? -1 : live.indexWhere((RoomMember m) => m.id == meId);
          if (pin < 0) pin = live.indexWhere((RoomMember m) => m.isOwner);
          if (pin < 0) pin = 0;
          final RoomMember pinned = live[pin];
          final List<RoomMember> rest = <RoomMember>[...live]..removeAt(pin);
          return SizedBox(
            height: 30,
            child: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _chip(pinned, snap),
                ),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.only(left: 4, right: 8),
                          itemCount: rest.length,
                          separatorBuilder: (BuildContext c, int i) =>
                              const SizedBox(width: 6),
                          itemBuilder: (BuildContext ctx, int i) =>
                              Center(child: _chip(rest[i], snap)),
                        ),
                      ),
                      // 末尾淡出：告诉用户「还能往右滚」
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 24,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: <Color>[
                                  AppColors.bg.withValues(alpha: 0),
                                  AppColors.bg,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: AppColors.text)),
      );

  /// 长按成员：房主弹底部菜单，其他人直接返回（长按无反应）。
  Future<void> _openMemberSheet(RoomMember m, RoomSnapshot snap) async {
    final RoomMember? me = snap.memberById(widget.memberId ?? '');
    final bool iAmHost = me?.isOwner ?? false;
    if (!iAmHost) return;
    // 房主自己不给菜单：禁言自己 / 把自己移出都没意义
    if (m.id == snap.hostId || m.id == (widget.memberId ?? '')) return;
    final String name =
        (m.nickname.isEmpty ? '成员' : m.nickname) + (m.isBot ? ' 🤖' : '');
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              dense: true,
              title: Text(name,
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(m.muted ? Icons.volume_up : Icons.volume_off,
                  size: 20, color: AppColors.text),
              title: Text(m.muted ? '解除禁言' : '禁言',
                  style: TextStyle(fontSize: 14, color: AppColors.text)),
              onTap: () => Navigator.of(ctx).pop(m.muted ? 'unmute' : 'mute'),
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined,
                  size: 20, color: AppColors.danger),
              title: Text('移出房间',
                  style: TextStyle(fontSize: 14, color: AppColors.danger)),
              onTap: () => Navigator.of(ctx).pop('kick'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    debugPrint('[YQK-ROOM] 成员菜单 action=$action member=${m.id} muted=${m.muted}');
    if (action == 'mute') widget.onMute?.call(m.id, true);
    if (action == 'unmute') widget.onMute?.call(m.id, false);
    if (action == 'kick') widget.onKick?.call(m.id);
  }

  Widget _chip(RoomMember m, RoomSnapshot snap) => GestureDetector(
        // 长按只对房主有效，判定放在 _openMemberSheet 里（普通人按了没反应）。
        // Bot 不是真人：踢人/禁言/转房主对它都没意义，所以整块不弹（不是弹出来再禁用）。
        onLongPress: m.isBot ? null : () => _openMemberSheet(m, snap),
        child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              m.online ? Icons.circle : Icons.circle_outlined,
              size: 8,
              color: m.online ? AppColors.success : AppColors.textDim,
            ),
            const SizedBox(width: 6),
            Text(
              (m.nickname.isEmpty ? '成员' : m.nickname) + (m.isBot ? ' 🤖' : ''),
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.text,
                  fontWeight: FontWeight.w600),
            ),
            if (m.isOwner) ...<Widget>[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(L.of(context).roomHost,
                    style: TextStyle(fontSize: 10, color: AppColors.primary)),
              ),
            ],
            if (m.muted) ...<Widget>[
              const SizedBox(width: 4),
              Icon(Icons.volume_off, size: 12, color: AppColors.textDim),
            ],
            // 语音标：在语音里的人昵称前挂一个绿色小麦克风（B 站/YY 的通行画法）
            if (widget.voiceIds.contains(m.id)) ...<Widget>[
              const SizedBox(width: 4),
              Icon(Icons.mic, size: 12, color: AppColors.success),
            ],
          ],
        ),
      ),
      );
}

/// 跟随条：贴在控制条上方（房主 64、客人 8），只在差 ≥2s 时出现。
class RoomFollowBar extends StatefulWidget {
  const RoomFollowBar({
    super.key,
    required this.snapshot,
    required this.memberId,
    required this.isHost,
    this.expected,
    this.myPosition,
    this.onSeek,
    this.embedded = false,
  });

  final ValueListenable<RoomSnapshot?> snapshot;
  final String? memberId;
  final bool isHost;
  final Duration? Function()? expected;

  /// 本机播放器的实时位置（由播放页传入）。不再用 members[].progress —— 那是上次上报值，暂停后不动。
  final Duration? Function()? myPosition;
  final ValueChanged<Duration>? onSeek;

  /// true = 排在视频下面，false = 浮在视频里
  final bool embedded;

  @override
  State<RoomFollowBar> createState() => _RoomFollowBarState();
}

class _RoomFollowBarState extends State<RoomFollowBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _slot(
      embedded: widget.embedded,
      bottom: widget.isHost ? 64 : 8,
      child: ValueListenableBuilder<RoomSnapshot?>(
        valueListenable: widget.snapshot,
        builder: (BuildContext context, RoomSnapshot? snap, Widget? _) {
          if (snap == null) return const SizedBox.shrink();
          final Duration? auth = widget.expected?.call();
          final Duration? mine = widget.myPosition?.call();
          if (auth == null || mine == null) return const SizedBox.shrink();
          final Duration lag = auth - mine;
          if (lag.abs() < const Duration(seconds: 2)) {
            return const SizedBox.shrink();
          }
          final bool behind = lag > Duration.zero;
          return Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    behind ? '你落后 ${lag.inSeconds} 秒' : '你领先 ${-lag.inSeconds} 秒',
                    style: TextStyle(fontSize: 12, color: AppColors.text),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => widget.onSeek?.call(auth),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(behind ? '跟上' : '等一下',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 房主控制条：贴视频底（bottom 8），只有房主才渲染。
class RoomHostBar extends StatefulWidget {
  const RoomHostBar({
    super.key,
    required this.snapshot,
    required this.memberId,
    this.onTransfer,
    this.onKick,
    this.onMute,
    this.onControlMode,
    this.onDanmakuSettings,
    this.onBotConfig,
    this.onPickMedia,
    this.onWebWatch,
    this.onScreenShare,
    this.screenSharingActive = false,
    this.onCastDlna,
    this.onLocalMedia,
    this.onReplay,
    this.onDebugSendDanmaku,
    this.onDebugSendTrio,
    this.embedded = false,
  });

  final ValueListenable<RoomSnapshot?> snapshot;
  final String? memberId;
  final ValueChanged<String>? onTransfer;
  final ValueChanged<String>? onKick;

  /// true = 排在视频下面，false = 浮在视频里
  final bool embedded;

  /// 禁言/解除禁言：(memberId, muted)
  final void Function(String memberId, bool muted)? onMute;

  /// 切换控制模式：'free' / 'host'（只有房主能用）
  final ValueChanged<String>? onControlMode;

  /// 打开弹幕设置面板（⋯ 菜单里的「弹幕设置」）
  final VoidCallback? onDanmakuSettings;

  /// 打开「房间 Bot」配置页（⋯ 菜单里，只有房主才传这个回调）
  final VoidCallback? onBotConfig;
  /// 房主专属：换片源（进选片模式，选中后整房切片）
  final VoidCallback? onPickMedia;

  /// D22：打开「一起看网页」（⋯ 菜单里，同样只有房主才传）
  final VoidCallback? onWebWatch;

  /// D20：共享屏幕（⋯ 菜单，只有房主才传；共享中文案变「停止共享」）
  final VoidCallback? onScreenShare;

  /// 屏幕共享是否正在进行，决定菜单文案
  final bool screenSharingActive;

  /// M10 B 组：投到电视（DLNA 发送端）。只有房主传这个回调。
  final VoidCallback? onCastDlna;

  /// M10 D 组：本机视频（局域网媒体库）。只有房主传这个回调。
  final VoidCallback? onLocalMedia;

  /// H11：打开本房间回放（房主与客人都能看）
  final VoidCallback? onReplay;

  /// debug 专用：用播放器当前位置发一条弹幕，验证「drawn>0 且位置对齐」。
  /// 只在 kDebugMode 且非 null 时出现在 ⋯ 菜单里，release 包里没有这一项。
  final VoidCallback? onDebugSendDanmaku;

  /// debug 专用：发短/中/长三条（宽度 90/360/440），用于穿屏时间与截断验收
  final VoidCallback? onDebugSendTrio;

  @override
  State<RoomHostBar> createState() => _RoomHostBarState();
}

class _RoomHostBarState extends State<RoomHostBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// 成员入口：action=all 时先选人再给三个动作；transfer/mute/kick 时选人即执行。
  Future<void> _openMembers(RoomSnapshot snap, String action) async {
    final List<RoomMember> others = snap.members
        .where((RoomMember m) => m.id != snap.hostId)
        .toList(growable: false);
    if (others.isEmpty) return;
    final RoomMember? picked = await showModalBottomSheet<RoomMember>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text('房间成员',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ),
            for (final RoomMember m in others)
              ListTile(
                title: Text(m.nickname.isEmpty ? '成员' : m.nickname),
                subtitle: m.muted
                    ? Text('已禁言',
                        style: TextStyle(fontSize: 11, color: AppColors.textDim))
                    : null,
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (action == 'transfer') {
      widget.onTransfer?.call(picked.id);
      return;
    }
    if (action == 'kick') {
      widget.onKick?.call(picked.id);
      return;
    }
    if (action == 'mute') {
      widget.onMute?.call(picked.id, !picked.muted);
      return;
    }
    await _memberActions(picked);
  }

  Future<void> _memberActions(RoomMember m) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(m.nickname.isEmpty ? '成员' : m.nickname,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textDim)),
              ),
            ),
            ListTile(
              leading: Icon(m.muted ? Icons.volume_up : Icons.volume_off),
              title: Text(m.muted ? '解除禁言' : '禁言'),
              onTap: () => Navigator.of(ctx).pop('mute'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('移交房主'),
              onTap: () => Navigator.of(ctx).pop('transfer'),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove),
              title: const Text('移出房间'),
              onTap: () => Navigator.of(ctx).pop('kick'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'mute') widget.onMute?.call(m.id, !m.muted);
    if (action == 'transfer') widget.onTransfer?.call(m.id);
    if (action == 'kick') widget.onKick?.call(m.id);
  }

  @override
  Widget build(BuildContext context) {
    return _slot(
      embedded: widget.embedded,
      bottom: 8,
      child: ValueListenableBuilder<RoomSnapshot?>(
        valueListenable: widget.snapshot,
        builder: (BuildContext context, RoomSnapshot? snap, Widget? _) {
          if (snap == null) return const SizedBox.shrink();
          final RoomMember? me = snap.memberById(widget.memberId ?? '');
          if (me == null || !me.isOwner) return const SizedBox.shrink();
          final bool free = snap.controlMode == 'free';
          // 「N 人在看」只数在线的人：members 里还留着已经走了的历史成员
          // （他们只是 online=false），用 length 会把走掉的人也算进去。
          final int watching =
              snap.members.where((RoomMember m) => m.online).length;
          // M8 布局收口：控制条只留房主专属动作（播放/暂停与进度条归视频内的主控制层）
          return Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  watching <= 1 ? '房主控制 · 仅你一人' : '房主控制 · $watching 人在看',
                  style: TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
                const Spacer(),
                IconButton(
                  tooltip: free ? '已锁定（自由共控）' : '锁定播放',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: Icon(
                    free ? Icons.lock_open : Icons.lock_outline,
                    color: AppColors.text,
                    size: 20,
                  ),
                  onPressed: () =>
                      widget.onControlMode?.call(free ? 'host' : 'free'),
                ),
                IconButton(
                  tooltip: L.of(context).roomMembers,
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: Icon(Icons.people_outline,
                      color: AppColors.text, size: 20),
                  onPressed: () => _openMembers(snap, 'all'),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: Icon(Icons.more_horiz,
                      color: AppColors.text, size: 20),
                  onSelected: (String v) {
                    if (v == 'danmaku') {
                      widget.onDanmakuSettings?.call();
                      return;
                    }
                    if (v == 'bot') {
                      widget.onBotConfig?.call();
                      return;
                    }
                    if (v == 'share') {
                      // 分享房间 = 打开本机服务那张二维码落地页：页面上能扫码、
                      // 能复制 https://…/r/<code> 链接。这个地址只有本机能开，
                      // 所以写死 127.0.0.1，不走 resolveServerBase。
                      unawaited(launchUrl(
                        Uri.parse('http://127.0.0.1:8080/local/qr'),
                        mode: LaunchMode.externalApplication,
                      ));
                      return;
                    }
                    if (v == 'pick') {
                      widget.onPickMedia?.call();
                      return;
                    }
                    if (v == 'replay') {
                      widget.onReplay?.call();
                      return;
                    }
                    if (v == 'web') {
                      widget.onWebWatch?.call();
                      return;
                    }
                    if (v == 'cast') {
                      widget.onCastDlna?.call();
                      return;
                    }
                    if (v == 'localmedia') {
                      widget.onLocalMedia?.call();
                      return;
                    }
                    if (v == 'screen') {
                      widget.onScreenShare?.call();
                      return;
                    }
                    if (v == 'debug-dm') {
                      widget.onDebugSendDanmaku?.call();
                      return;
                    }
                    if (v == 'debug-dm-len') {
                      widget.onDebugSendTrio?.call();
                      return;
                    }
                    _openMembers(snap, v);
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                        value: 'danmaku', child: Text(L.of(context).roomDanmaku)),
                    // 房主专属：服务端 handleBotConfig 只认房主（非房主回 not_host），
                    // 所以入口只挂在房主菜单上，客人那份菜单根本不会出现。
                    if (widget.onBotConfig != null)
                      PopupMenuItem<String>(
                          value: 'bot', child: Text(L.of(context).roomBot)),
                    // 分享房间：把扫码页/落地页链接给房主自己看，好转发给朋友。
                    // 与 Bot 同一个门槛（只有房主那份菜单里 onBotConfig 非空）。
                    if (widget.onBotConfig != null)
                      PopupMenuItem<String>(
                          value: 'share', child: Text(L.of(context).roomShare)),
                    // 换片源：只有房主能发起（服务端 relay 不看身份，靠这里不挂客人菜单）
                    if (widget.onPickMedia != null)
                      PopupMenuItem<String>(
                          value: 'pick', child: Text('换片源')),
                    // D22：一起看网页（第一轮只做打开 + 滚动同步）。同 Bot 一样只挂房主菜单。
                    if (widget.onWebWatch != null)
                      PopupMenuItem<String>(
                          value: 'web', child: Text('一起看网页')),
                    // M10 B 组：投到电视（DLNA 发送端，SSDP 搜索 + SOAP 控制）
                    if (widget.onCastDlna != null)
                      PopupMenuItem<String>(
                          value: 'cast', child: Text('投到电视')),
                    // M10 D 组：本机视频（列 /sdcard/Movies 里的片，直接播）
                    if (widget.onLocalMedia != null)
                      PopupMenuItem<String>(
                          value: 'localmedia', child: Text('本机视频')),
                    // H11：本房间回放（房主与客人都能看）
                    if (widget.onReplay != null)
                      PopupMenuItem<String>(
                          value: 'replay', child: Text('本房间回放')),
                    // D20：共享屏幕。第一步只在本机起采集，不推流、不进房间。
                    if (widget.onScreenShare != null)
                      PopupMenuItem<String>(
                          value: 'screen',
                          child: Text(
                              widget.screenSharingActive ? '停止共享' : L.of(context).roomScreenShare)),
                    // 只在 debug 包里出现：用途是验证「drawn>0 且位置对齐」——
                    // 它直接读播放器当前位置发一条弹幕，不经过任何上报路径。
                    if (kDebugMode && widget.onDebugSendDanmaku != null)
                      PopupMenuItem<String>(
                          value: 'debug-dm', child: Text('在当前位置发一条弹幕（调试）')),
                    // 同上，debug 专用：一次发短/中/长三条（约 90/360/440px），
                    // 用来验收「固定时间 8 秒穿屏」和「超长截断 + …」。
                    if (kDebugMode && widget.onDebugSendTrio != null)
                      PopupMenuItem<String>(
                          value: 'debug-dm-len', child: Text('发短/中/长弹幕（调试）')),
                    PopupMenuItem<String>(
                        value: 'transfer', child: Text('移交房主')),
                    PopupMenuItem<String>(
                        value: 'mute', child: Text('禁言 / 解除禁言')),
                    PopupMenuItem<String>(value: 'kick', child: Text('移出房间')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 全屏时用的唯一浮层：右上角「N 人在看」。
class RoomFullscreenPill extends StatelessWidget {
  const RoomFullscreenPill({super.key, required this.snapshot});

  final ValueListenable<RoomSnapshot?> snapshot;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 10,
      top: 8,
      child: RoomFullscreenPillBody(snapshot: snapshot),
    );
  }
}

/// 同上，但不带 Positioned —— 要和房主锁定按钮排一行时用这份。
class RoomFullscreenPillBody extends StatelessWidget {
  const RoomFullscreenPillBody({super.key, required this.snapshot});

  final ValueListenable<RoomSnapshot?> snapshot;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RoomSnapshot?>(
      valueListenable: snapshot,
      builder: (BuildContext context, RoomSnapshot? snap, Widget? _) {
        if (snap == null) return const SizedBox.shrink();
        final int online = snap.members.where((RoomMember m) => m.online).length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$online 人在看',
              style: TextStyle(fontSize: 11, color: AppColors.text)),
        );
      },
    );
  }
}

/// 全屏右上角的房主锁定按钮：只做 control_mode 开关，别的动作都不进全屏。
class FullscreenHostLock extends StatelessWidget {
  const FullscreenHostLock({
    super.key,
    required this.snapshot,
    required this.onControlMode,
  });

  final ValueListenable<RoomSnapshot?> snapshot;
  final ValueChanged<String>? onControlMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RoomSnapshot?>(
      valueListenable: snapshot,
      builder: (BuildContext context, RoomSnapshot? snap, Widget? _) {
        if (snap == null) return const SizedBox.shrink();
        final bool free = snap.controlMode == 'free';
        return GestureDetector(
          onTap: () => onControlMode?.call(free ? 'host' : 'free'),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              free ? Icons.lock_open : Icons.lock_outline,
              size: 18,
              color: AppColors.text,
            ),
          ),
        );
      },
    );
  }
}

/// 房主侧：有人请求控制权时浮在成员条下方的一条（8 秒倒计时，到点自动忽略）。
class ClaimBar extends StatefulWidget {
  const ClaimBar({
    super.key,
    required this.claim,
    this.onAllow,
    this.onIgnore,
  });

  /// claim 帧原样（fromName / action / rid / ttl）
  final Map<String, dynamic>? claim;
  final void Function(Map<String, dynamic> claim)? onAllow;
  final void Function(Map<String, dynamic> claim)? onIgnore;

  @override
  State<ClaimBar> createState() => _ClaimBarState();
}

class _ClaimBarState extends State<ClaimBar> {
  Timer? _tick;
  int _left = 8;
  String? _rid;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant ClaimBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? rid = widget.claim?['rid'] as String?;
    if (rid != _rid) _arm();
  }

  void _arm() {
    _tick?.cancel();
    _rid = widget.claim?['rid'] as String?;
    if (_rid == null) return;
    _left = ((widget.claim?['ttl'] as num?)?.toInt() ?? 8000) ~/ 1000;
    if (_left <= 0) _left = 8;
    _tick = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      setState(() {
        _left -= 1;
        if (_left <= 0) {
          t.cancel();
          final Map<String, dynamic>? c = widget.claim;
          if (c != null) widget.onIgnore?.call(c);
        }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _label(String action) {
    switch (action) {
      case 'pause':
        return '暂停';
      case 'play':
        return '播放';
      case 'seek':
        return '跳进度';
      default:
        return action;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? c = widget.claim;
    if (c == null) return const SizedBox.shrink();
    final String who = (c['fromName'] as String?)?.trim().isNotEmpty == true
        ? c['fromName'] as String
        : '有人';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$who 请求${_label((c['action'] as String?) ?? '')} · ${_left}s',
              style: TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => widget.onAllow?.call(c),
            child: const Text('允许'),
          ),
          TextButton(
            onPressed: () => widget.onIgnore?.call(c),
            child: const Text('忽略'),
          ),
        ],
      ),
    );
  }
}
/// 说话条：房间里的最小输入框（E 项只建了数据通道，这里补一个能打字的口子）。
///
/// 被禁言的人：输入框禁用 + placeholder 换成「你被禁言了」，
/// 别让人打完一长句才被服务端 errObj(muted) 打回来。
class RoomChatBar extends StatefulWidget {
  const RoomChatBar({
    super.key,
    required this.snapshot,
    required this.memberId,
    this.onSend,
    this.embedded = false,
    this.danmakuEnabled = true,
    this.onDanmakuToggle,
    this.voiceJoined = false,
    this.voiceFull = false,
    this.voiceEnabled = true,
    this.onVoiceTap,
    this.onVoiceLeave,
  });

  final ValueListenable<RoomSnapshot?> snapshot;
  final String? memberId;
  final ValueChanged<String>? onSend;

  /// true = 排在视频下面（键盘弹起时贴着键盘上沿），false = 浮在视频里
  final bool embedded;

  /// 「发聊天时顺带发弹幕」的开关状态：只用来画图标高亮，状态由上层持有。
  final bool danmakuEnabled;

  /// 点开关时往上抛。这里刻意不碰 RoomClient / SharedPreferences：
  /// 说话条只管显示和转发意图，发不发帧是播放页的事。
  final ValueChanged<bool>? onDanmakuToggle;

  /// 我在不在语音里（高亮麦克风 + 长按退出）
  final bool voiceJoined;

  /// 上一次 join 被语音房满拒了：按钮置灰，点了只提示
  final bool voiceFull;

  /// 服务端语音总开关（GET /local/features）。false 时麦克风整个不渲染 ——
  /// 不渲染而不是禁用：置灰会让人以为「点一下能用」。
  final bool voiceEnabled;

  /// 点麦克风：加入 / 已有则由上层解释为「什么都不做」
  final VoidCallback? onVoiceTap;

  /// 长按麦克风：退出语音
  final VoidCallback? onVoiceLeave;

  @override
  State<RoomChatBar> createState() => _RoomChatBarState();
}

class _RoomChatBarState extends State<RoomChatBar> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final String t = _text.text.trim();
    if (t.isEmpty) return;
    widget.onSend?.call(t);
    _text.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _slot(
      embedded: widget.embedded,
      bottom: 52,
      child: ValueListenableBuilder<RoomSnapshot?>(
        valueListenable: widget.snapshot,
        builder: (BuildContext context, RoomSnapshot? snap, Widget? _) {
          if (snap == null) return const SizedBox.shrink();
          final RoomMember? me = snap.memberById(widget.memberId ?? '');
          final bool muted = me?.muted ?? false;
          return Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: muted ? 0.55 : 0.9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: <Widget>[
                // 弹幕开关：开 = 字幕图标 + 主色；关 = 划掉的图标 + 灰。
                // 放在输入框左边（B 站 / 抖音都是这个位置），不抢发送键。
                IconButton(
                  onPressed: widget.onDanmakuToggle == null
                      ? null
                      : () => widget.onDanmakuToggle!(!widget.danmakuEnabled),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 28),
                  // I-85：关掉后光变灰不够显眼，图标换带斜杠的，井号环也别丢
                  tooltip: widget.danmakuEnabled
                      ? '发弹幕：开'
                      : '发弹幕：关（点击开启）',
                  icon: Icon(
                    widget.danmakuEnabled
                        ? Icons.subtitles_outlined
                        : Icons.comments_disabled_outlined,
                    size: 17,
                    color: widget.danmakuEnabled
                        ? AppColors.primary
                        : AppColors.textDim,
                  ),
                ),
                // 语音开关：不在语音 = 线性灰麦克风；在语音 = 实心主色，长按退出。
                // 用 InkWell 而不是 IconButton + 外层 GestureDetector：IconButton 内部
                // 带 Tooltip，Tooltip 在手机上会吃掉长按（弹提示），长按永远到不了外层。
                if (widget.voiceEnabled)
                  Semantics(
                    label: widget.voiceJoined ? '语音中（长按退出）' : '加入语音',
                    button: true,
                    child: SizedBox(
                      width: 30,
                      height: 28,
                      child: InkWell(
                        onTap: widget.onVoiceTap,
                        onLongPress:
                            widget.voiceJoined ? widget.onVoiceLeave : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Icon(
                          widget.voiceJoined ? Icons.mic : Icons.mic_none,
                          size: 17,
                          color: widget.voiceJoined
                              ? AppColors.primary
                              : AppColors.textDim,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    enabled: !muted,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    style: TextStyle(
                        fontSize: 12,
                        color: muted ? AppColors.textDim : AppColors.text),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: muted ? '你被禁言了' : '说点什么…',
                      hintStyle: TextStyle(
                          fontSize: 12, color: AppColors.textDim),
                    ),
                  ),
                ),
                if (!muted)
                  IconButton(
                    onPressed: _submit,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(Icons.send, size: 16,
                        color: AppColors.primary),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}