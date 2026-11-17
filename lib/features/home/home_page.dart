import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/local/prefs.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/room/lan_discovery.dart';
import '../../routing/routes.dart';
import '../../theme/app_theme.dart';
import '../library/library_page.dart';
import '../onboarding/onboarding_overlay.dart';
import '../room/room_entry.dart';
import '../settings/settings_page.dart';

/// P01 首页 —— 最近观看区留白，等 M6 详情页/片库接上再填内容。
/// 正式 UI 不放任何调试入口（06 §2 MUST NOT 第 11 条）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 0 = 首页，1 = 我的（底部导航第二个 tab；原有 AppBar 入口一个都没动）
  int _tab = 0;

  // G5 三步引导的定位锚：搜片 / 我的 tab / 建房
  final GlobalKey _guideSources = GlobalKey(debugLabel: 'guide-search');
  final GlobalKey _guideNav = GlobalKey(debugLabel: 'guide-nav');
  final GlobalKey _guideCreate = GlobalKey(debugLabel: 'guide-create');
  bool _guideTried = false;

  @override
  void initState() {
    super.initState();
    // 首帧之后再看要不要弹（这时候 GlobalKey 才有 RenderBox）
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeGuide());
    OnboardingGate.request.addListener(_onGate);
  }

  @override
  void dispose() {
    OnboardingGate.request.removeListener(_onGate);
    super.dispose();
  }

  void _onGate() {
    if (!mounted) return;
    unawaited(_runGuide(force: true));
  }

  Future<void> _maybeGuide() async {
    if (_guideTried) return;
    _guideTried = true;
    await _runGuide(force: false);
  }

  /// [force] = 用户在设置里点了「重新看一遍引导」，忽略 done 标记
  Future<void> _runGuide({required bool force}) async {
    final Prefs prefs = await Prefs.open();
    final bool done = prefs.getBool(PrefKeys.onboardingDone) ?? false;
    if (done && !force) {
      debugPrint('[YQK-GUIDE] skip done=true');
      return;
    }
    if (!mounted || _tab != 0) return;
    await OnboardingOverlay.show(
      context,
      prefs: prefs,
      steps: <OnboardingStep>[
        OnboardingStep(
          key: _guideSources,
          title: '搜片',
          desc: '从这里进片源，支持多个源同时搜索。',
        ),
        OnboardingStep(
          key: _guideNav,
          title: '我的',
          desc: '收藏、追番、历史和下载都在这儿。',
          // 底部导航只高亮右半（「我的」那一格）
          fraction: const Rect.fromLTRB(0.5, 0, 1, 1),
        ),
        OnboardingStep(
          key: _guideCreate,
          title: '建房',
          desc: '建房后别人用房间码就能进来一起看。',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final L t = L.of(context);
    return FocusTraversalGroup(
      // G3：D-pad / 遥控器按「视觉顺序」走焦点，不做环形回绕
      policy: ReadingOrderTraversalPolicy(),
      child: Scaffold(
      appBar: AppBar(
        title: Text(t.appName),
        actions: <Widget>[
          // 一起看：建房 → 直接进播放页
          IconButton(
            key: _guideCreate,
            autofocus: true,
            tooltip: t.homeCreateRoom,
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () async {
              final String? url = await demoStreamUrl();
              if (!context.mounted) return;
              if (url == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('本地还没片子，先去「片源」挑一部')),
                );
                return;
              }
              await createRoomAndEnter(context, title: '一起看', videoUrl: url);
            },
          ),
          // 加入房间：输入房间码，以客人身份连房（跟房主播放走）
          IconButton(
            tooltip: t.homeJoinRoom,
            icon: const Icon(Icons.login),
            onPressed: () async {
              final String? code = await _askRoomCode(context);
              if (code == null || !context.mounted) return;
              await joinRoomAndEnter(context, code, from: JoinFrom.manual);
            },
          ),
          // 扫码加房：pop 回来的就是房间码（解析在 ScanPage 里做）
          IconButton(
            tooltip: t.homeScan,
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final String? code =
                  await context.push<String>('/scan');
              if (code == null || !context.mounted) return;
              await joinRoomAndEnter(context, code, from: JoinFrom.scan);
            },
          ),
          // 片源是产品功能（M4），不是调试入口：从这里进 P05 浏览/加源
          IconButton(
            tooltip: '网盘',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => context.push(Routes.netdisk),
          ),
          IconButton(
            key: _guideSources,
            tooltip: t.homeSources,
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => context.push(Routes.sources),
          ),
          // 设置：目前只放 D26 的房间通道策略，要在进房前就能改。
          IconButton(
            tooltip: t.homeSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const SettingsPage(),
              ),
            ),
          ),
          // 语音：首页这一颗是「不在房间」状态的入口。
          // 真语音成员在房间页的说话条上（要跟着 roomClient 的成员表走）；
          // 这里点只提示先建房/进房 —— 没有房间就没有成员身份，
          // 发 voice join 服务端只会回 no-room，不如本地就说清楚。
          IconButton(
            tooltip: '语音（需先进入房间）',
            icon: const Icon(Icons.mic_none),
            onPressed: () {
              debugPrint('[YQK-VOICE] join blocked not-in-room (home)');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('先进房间')),
              );
            },
          ),
        ],
      ),
      body: _tab == 0
          ? ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.page,
                vertical: AppSpace.md,
              ),
              children: <Widget>[
          Text('最近观看', style: AppText.section),
          const SizedBox(height: AppSpace.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Column(
              children: <Widget>[
                Icon(Icons.play_circle_outline,
                    size: 36, color: AppColors.textDim),
                SizedBox(height: AppSpace.xs),
                Text('还没有看过的片子', style: AppText.body),
                SizedBox(height: AppSpace.xxs),
                Text('先去「片源」挑一部，看过就会记在这儿', style: AppText.sub),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.sources),
            icon: const Icon(Icons.search),
            label: const Text('去片源里搜点什么'),
          ),
          const SizedBox(height: AppSpace.xl),
              Center(child: Text(kBrandLine, style: AppText.label)),
              ],
            )
          : const LibraryPage(embedded: true),
      bottomNavigationBar: NavigationBar(
        key: _guideNav,
        selectedIndex: _tab,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: t.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: t.tabLibrary,
          ),
        ],
      ),
      ),
    );
  }
  /// 输入房间码（6 位左右，自动转大写）
  ///
  /// 不用 TextEditingController：`Navigator.pop` 让 Future 立刻完成，而弹窗 route
  /// 还要播 150ms 退出动画，此刻 EditableText 仍持有 controller 的监听器；
  /// 提前 dispose 会让动画结束时 removeListener 打到已 dispose 的对象，
  /// 触发 framework.dart:6268 `_dependents.isEmpty` 断言（红屏）。
  Future<String?> _askRoomCode(BuildContext context) async {
    String text = '';
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('加入房间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // D25：附近的房间（只在收到广播时出现；点卡片直接拿它的码去加入）
            _NearbyRooms(
              onPick: (String c) => Navigator.of(ctx).pop(c.toUpperCase()),
            ),
            TextField(
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: '房间码，比如 K3F9Q2'),
              onChanged: (String v) => text = v,
              onSubmitted: (String v) => Navigator.of(ctx).pop(v.trim()),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(text.trim()),
            child: const Text('进去'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return null;
    return code.toUpperCase();
  }
}

/// D25 接收端：房间列表页里「附近的房间」横条。
///
/// 只在对话框活着时监听 45231（dispose 里 stop），空列表不占位、不显示标题。
class _NearbyRooms extends StatefulWidget {
  const _NearbyRooms({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  State<_NearbyRooms> createState() => _NearbyRoomsState();
}

class _NearbyRoomsState extends State<_NearbyRooms> {
  final LanDiscovery _discovery = LanDiscovery(selfCode: lastRoomCode);
  List<LanRoom> _rooms = const <LanRoom>[];

  @override
  void initState() {
    super.initState();
    _discovery.onRooms = (List<LanRoom> rooms) {
      if (mounted) setState(() => _rooms = rooms);
    };
    _discovery.start();
  }

  @override
  void dispose() {
    _discovery.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rooms.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('附近的房间', style: AppText.sub),
        const SizedBox(height: AppSpace.xs),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _rooms.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
            itemBuilder: (BuildContext context, int i) {
              final LanRoom r = _rooms[i];
              return InkWell(
                onTap: () => widget.onPick(r.code),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: AppSpace.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        r.name.isEmpty ? r.code : r.name,
                        style: AppText.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${r.host.isEmpty ? '房主' : r.host} · ${r.code}',
                        style: AppText.sub,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
    );
  }
}