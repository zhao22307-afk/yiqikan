import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/deeplink/deeplink_bridge.dart';
import 'core/deeplink/parse.dart';
import 'core/error/error_page.dart';
import 'core/notify/notifier.dart';
import 'core/theme/theme_controller.dart';
import 'data/local/prefs.dart';
import 'data/sources/tvbox_importer.dart';
import 'features/room/room_entry.dart';
import 'l10n/gen/app_localizations.dart';
import 'providers/app_providers.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

/// 应用根组件：主题 + 字号 + 路由 + 标题。
class YiqikanApp extends ConsumerStatefulWidget {
  const YiqikanApp({super.key, this.initialLocation});

  /// 启动深链（`/play?url=...`）；为空就正常进首页
  final String? initialLocation;

  @override
  ConsumerState<YiqikanApp> createState() => _YiqikanAppState();
}

class _YiqikanAppState extends ConsumerState<YiqikanApp>
    with WidgetsBindingObserver {
  // 路由只建一次，避免 rebuild 把 GoRouter 状态重置（MUST NOT 之一）。
  late final GoRouter _router =
      buildRouter(initialLocation: widget.initialLocation);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 深链进房：冷启动那条由 getInitialLink 取，前台态那条由 onDeepLink 推进来。
    DeepLinkBridge.attach(_openRoomLink);
    // G9：通知被点（房间邀请 / 播放控制）→ 对应动作
    AppNotifier.handler = _onNotifyAction;
    // G7：崩溃兜底页的「重试」= 回首页（不杀进程）。
    ErrorReset.onReset = () {
      debugPrint('[YQK-ERR] reset -> home');
      _router.go('/');
    };
    // TVBox：把 assets 里的 dianshi.json 导进 sources（只导一次，幂等）
    unawaited(_importTvboxOnce());
  }

  /// 内置 TVBox 源的首次导入。
  ///
  /// 用 prefs 里的标记 + 表内 (kind, api, ext) 判重双保险：标记丢了也不会重复插。
  Future<void> _importTvboxOnce() async {
    try {
      final Prefs prefs = await Prefs.open();
      if (prefs.getBool('tvbox_builtin_imported_v1') == true) {
        debugPrint('[YQK-TVBOX] import builtin skipped（已导入过）');
        return;
      }
      // initState 里不能读 provider，等第一帧落地
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final TvboxImporter importer =
          TvboxImporter(service: ref.read(sourceServiceProvider));
      final int added = await importer.importBuiltin();
      await prefs.setBool('tvbox_builtin_imported_v1', true);
      debugPrint('[YQK-TVBOX] import builtin marked added=$added');
    } on Object catch (e) {
      debugPrint('[YQK-TVBOX] import builtin failed: $e');
    }
  }

  @override
  void dispose() {
    ErrorReset.onReset = null;
    AppNotifier.handler = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 通知栏回调：
  /// - 房间邀请：payload `room:<code>` → 走深链进房（跟点分享链接同一条路）
  /// - 后台播放：prev / toggle / next → 交给播放页注册的 [PlayerRemote.onAction]
  void _onNotifyAction(String action, String? payload) {
    debugPrint('[YQK-NOTIFY] action=$action payload=${payload ?? '-'}');
    if (payload != null && payload.startsWith('room:')) {
      final String code = payload.substring('room:'.length).trim();
      if (code.isNotEmpty) {
        // 通知上的「进入房间」是明确动作：直接进房，不再停在确认页。
        final NavigatorState? nav =
            _router.routerDelegate.navigatorKey.currentState;
        final BuildContext? navCtx = nav?.context;
        if (nav != null && navCtx != null) {
          nav.popUntil((Route<dynamic> r) => r.isFirst);
          unawaited(joinRoomAndEnter(navCtx, code.toUpperCase(),
              from: JoinFrom.deeplink));
        } else {
          _openRoomLink(RoomLink(code: code.toUpperCase(), raw: payload));
        }
      }
      return;
    }
    PlayerRemote.onAction?.call(action);
  }

  /// 「跟随系统」时系统切深浅色要跟着变（G2）。
  @override
  void didChangePlatformBrightness() {
    if (ThemeController.pref != ThemeModePref.system) return;
    final Brightness b =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    debugPrint('[YQK-THEME] platform brightness=${b.name}');
    setState(() {});
  }

  /// 当前应当生效的色板：偏好是 system 就看系统亮度。
  AppVariant _effective() {
    switch (ThemeController.pref) {
      case ThemeModePref.light:
        return AppVariant.light;
      case ThemeModePref.dark:
        return AppVariant.dark;
      case ThemeModePref.system:
        final Brightness b =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        return b == Brightness.dark ? AppVariant.dark : AppVariant.light;
    }
  }

  /// 深链 → 进房页（带来源标记，文案与手输/扫码区分）。
  ///
  /// 热态（已经在播放页）时走命令式 push：播放页是 Navigator.push 上去的，
  /// 压在 go_router 的页面栈之上，`go('/join')` 只会换掉底下那层，进房页永远
  /// 不会被 build，表现就是"深链没反应"。所以先 popUntil 到根，再 push 一层。
  void _openRoomLink(RoomLink link) {
    debugPrint(
        '[YQK-LINK] open code=${link.code} pwd=${link.pwd.isEmpty ? '(none)' : '(set)'} addr=${link.addr.isEmpty ? '(none)' : link.addr}');
    final NavigatorState? nav =
        _router.routerDelegate.navigatorKey.currentState;
    if (nav == null) {
      // 冷启动：第一帧还没建好，交给 go 走 /join 路由
      final String pwd = link.pwd.isEmpty
          ? ''
          : '&pwd=${Uri.encodeQueryComponent(link.pwd)}';
      // 分享落地页带来的房主地址要一路带到进房页（有值就别再探测通道）。
      final String addr = link.addr.isEmpty
          ? ''
          : '&addr=${Uri.encodeQueryComponent(link.addr)}';
      final String loc = '/join?code=${link.code}&from=deeplink$pwd$addr';
      debugPrint('[YQK-LINK] go $loc');
      _router.go(loc);
      return;
    }
    nav.popUntil((Route<dynamic> r) => r.isFirst);
    debugPrint('[YQK-LINK] push /join code=${link.code}');
    nav.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => JoinEntryPage(
          code: link.code,
          pwd: link.pwd,
          addr: link.addr,
          from: JoinFrom.deeplink,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeController.revision,
      builder: (BuildContext context, int _, Widget? __) {
        final AppVariant v = _effective();
        // 先写进控制器，下面整棵子树的 AppColors getter 才是对的色板。
        ThemeController.applyEffective(v);
        final bool dark = v == AppVariant.dark;
        return MaterialApp.router(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          // G1：多语言（ARB 驱动，L 是 output-class；zh 为模板）
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          locale: ThemeController.effectiveLocale,
          // G2：全局字号倍率（小 0.9 / 标准 1.0 / 大 1.15），叠加在系统缩放之上。
          builder: (BuildContext ctx, Widget? child) {
            final MediaQueryData mq = MediaQuery.of(ctx);
            final double sys = mq.textScaler.scale(1);
            final double scale = sys * ThemeController.fontScale;
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          routerConfig: _router,
        );
      },
    );
  }
}
