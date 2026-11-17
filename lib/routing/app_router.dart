import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_page.dart';
import '../features/library/media_library_page.dart';
import '../features/sources/source_add_page.dart';
import '../features/sources/import_page.dart';
import '../features/netdisk/netdisk_add_page.dart';
import '../features/netdisk/netdisk_browse_page.dart';
import '../features/netdisk/netdisk_page.dart';
import '../features/sources/sources_page.dart';
import '../features/sniffer/sniff_page.dart';
import '../features/player/player_controller.dart';
import '../platform/player/kernel_factory.dart';
import '../features/player/advanced_page.dart';
import '../features/player/player_page.dart';
import '../features/player/resolve_gate_page.dart';
import '../features/room/room_entry.dart';
import '../features/room/scan_page.dart';
import '../platform/player/anime4k.dart';
import 'routes.dart';

/// 路由装配入口。M0 只接 P01 首页，M2 接 P08 播放页，其余在各自里程碑里挂上。
/// [initialLocation] 给启动深链用：`yiqikan://play?url=file:///sdcard/Download/x.ts`
/// 会被 App 主入口翻译成 `/play?url=...` 传进来（05 §7 深链口径）。
GoRouter buildRouter({String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? Routes.home,
    routes: <RouteBase>[
      // 启动页占位：M1 换成真正的 splash（含内置服务就绪探测）
      GoRoute(
        path: Routes.splash,
        builder: (BuildContext context, GoRouterState state) =>
            const HomePage(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const HomePage(),
      ),
      // 深链入口：/play?url=&title=&start=&a4k=
      // 这是正常功能（本地文件/局域网地址唤起），不是调试口
      GoRoute(
        path: '/play',
        builder: (BuildContext context, GoRouterState state) =>
            _buildPlayer(state, fromQuery: true),
      ),
      // 深链进房：yiqikan://room/{code} → /join?code=XXXXXX&from=deeplink&pwd=
      // 分享落地页的按钮是 yiqikan://join?code=…&addr=…，addr 一路带到 JoinEntryPage。
      GoRoute(
        path: '/join',
        builder: (BuildContext context, GoRouterState state) => JoinEntryPage(
          code: state.uri.queryParameters['code'] ?? '',
          pwd: state.uri.queryParameters['pwd'] ?? '',
          addr: state.uri.queryParameters['addr'] ?? '',
          from: joinFromOf(state.uri.queryParameters['from']),
        ),
      ),
      // 扫码加房：扫到房间码就 pop 回上一页，由调用方 joinRoomAndEnter(from: scan)
      GoRoute(
        path: '/scan',
        builder: (BuildContext context, GoRouterState state) => ScanPage(
          // ?image= 只在 debug 包里认（真机验收用），正式链路一律开摄像头
          debugImagePath: kDebugMode
              ? state.uri.queryParameters['image']
              : null,
        ),
      ),
      GoRoute(
        path: Routes.player,
        builder: (BuildContext context, GoRouterState state) =>
            _buildPlayer(state, fromQuery: false),
      ),
      // F3 媒体库（E6 B 组）：扫本机目录、进子目录、点播复用 /player
      GoRoute(
        path: Routes.mediaLibrary,
        builder: (BuildContext context, GoRouterState state) =>
            const MediaLibraryPage(),
      ),
      // P05 浏览：源列表 + 聚合搜索（M4）
      GoRoute(
        path: Routes.sources,
        builder: (BuildContext context, GoRouterState state) =>
            const SourcesPage(),
      ),
      // P10 网盘：账号列表 / 添加 / 浏览（M6 第一段）
      GoRoute(
        path: Routes.netdisk,
        builder: (BuildContext context, GoRouterState state) =>
            const NetdiskPage(),
      ),
      GoRoute(
        path: Routes.netdiskAdd,
        builder: (BuildContext context, GoRouterState state) =>
            const NetdiskAddPage(),
      ),
      GoRoute(
        path: Routes.netdiskBrowse,
        builder: (BuildContext context, GoRouterState state) => NetdiskBrowsePage(
          accountId: state.uri.queryParameters['id'] ?? '',
          accountName: state.uri.queryParameters['name'] ?? '',
        ),
      ),
      // P04 添加源（M4）
      GoRoute(
        path: Routes.sourceAdd,
        builder: (BuildContext context, GoRouterState state) =>
            const SourceAddPage(),
      ),
      // P1c 导入配置：贴地址 / 粘 JSON / 单个源
      GoRoute(
        path: Routes.sourceImport,
        builder: (BuildContext context, GoRouterState state) =>
            const SourceImportPage(),
      ),
      // P09 网页嗅探（M5）：/sniff?url=... 可以直接带网址进来
      GoRoute(
        path: Routes.sniff,
        builder: (BuildContext context, GoRouterState state) => SniffPage(
          initialUrl: state.uri.queryParameters['url'],
        ),
      ),
      // 高级面板只在 debug 构建可见（05 §A11 / 06 §2 MUST NOT 第 11 条）
      GoRoute(
        path: Routes.playerAdvanced,
        builder: (BuildContext context, GoRouterState state) {
          if (!kDebugMode) {
            return const Scaffold(
              body: Center(child: Text('正式版没有这个页面')),
            );
          }
          final Object? extra = state.extra;
          return PlayerAdvancedPage(
            controller: extra is PlayerController ? extra : null,
          );
        },
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      appBar: AppBar(title: const Text('页面没找到')),
      body: Center(
        child: Text('这条路径还没接上：${state.uri}'),
      ),
    ),
  );
}

Widget _buildPlayer(GoRouterState state, {required bool fromQuery}) {
  final Object? extra = state.extra;
  // 调试构建：/play?resolve=1&url=... 先走一遍解析链再播（验收番剧/直播/缓存用）
  if (fromQuery && kDebugMode && state.uri.queryParameters['resolve'] == '1') {
    final String? raw = state.uri.queryParameters['url'];
    if (raw != null && raw.isNotEmpty) {
      return ResolveGatePage(
        url: raw,
        expireFirst: state.uri.queryParameters['expire'] == '1',
        repeat: int.tryParse(state.uri.queryParameters['repeat'] ?? '1') ?? 1,
        failKind: state.uri.queryParameters['fail'],
      );
    }
  }
  if (!fromQuery && extra is PlayerMedia) {
    return PlayerPage(media: extra, playlist: extra.playlist);
  }

  final Map<String, String> q = state.uri.queryParameters;
  final String? url = q['url'];
  if (url == null || url.isEmpty) {
    // 没有媒体就别"播放"了，给一句人话而不是黑屏
    return Scaffold(
      appBar: AppBar(title: const Text('播放')),
      body: const Center(child: Text('没有要播放的内容，回到上一页重新选一部')),
    );
  }
  final double startSec =
      double.tryParse(q['start'] ?? '') ?? 0;
  // 片源请求头（03 §3 sources.config 的 httpHeaders）：验收时用深链的
  // referer/ua 参数传进来，走的是和正式片源完全同一条 _headers 路径。
  final Map<String, String> headers = <String, String>{
    if ((q['referer'] ?? '').isNotEmpty) 'Referer': q['referer']!,
    if ((q['ua'] ?? '').isNotEmpty) 'User-Agent': q['ua']!,
  };
  final PlayerMedia media = PlayerMedia(
    id: q['id'] ?? url,
    title: q['title'] ?? '本地播放',
    url: url,
    sourceKind: q['kind'] ?? 'local',
    headers: headers,
  );
  return PlayerPage(
    media: media,
    // 显式带 start 就按它来：0 也照样传，别退回续播逻辑。
    startAt: q.containsKey('start')
        ? Duration(milliseconds: (startSec * 1000).round())
        : null,
    anime4k: _parseLevel(q['a4k']),
    autoplay: q['autoplay'] != '0',
    kernelKind: _parseKernel(q['kernel']),
    openAdvanced: q['advanced'] == '1',
    autoExitAfter: int.tryParse(q['exit'] ?? '') == null
        ? null
        : Duration(seconds: int.parse(q['exit']!)),
    audioTrack: int.tryParse(q['aid'] ?? ''),
    subtitlePath: q['sub'],
    rateOverride: double.tryParse(q['rate'] ?? ''),
    aspectIndex: int.tryParse(q['aspect'] ?? ''),
    audioFile: q['audiofile'],
    brightnessOverride: double.tryParse(q['bright'] ?? ''),
    volumeOverride: double.tryParse(q['vol'] ?? ''),
    subProps: _parseSubProps(q['subprops']),
    // 验收钩子（只在 debug 构建生效）：hold=<秒> 先跑起来再暂停并精确 seek，
    // 保证两次启动停在同一帧上做像素比对。
    holdAt: q.containsKey('hold')
        ? Duration(milliseconds: ((double.tryParse(q['hold']!) ?? 0) * 1000).round())
        : null,
  );
}

KernelKind? _parseKernel(String? raw) {
  switch (raw) {
    case 'mpv':
      return KernelKind.mpv;
    case 'fvp':
      return KernelKind.fvp;
    case 'auto':
      return KernelKind.auto;
    default:
      // 不传就用设置里存的偏好（默认自动）
      return null;
  }
}

Anime4kLevel _parseLevel(String? raw) {
  switch (raw) {
    case 'light':
    case 'low':
      return Anime4kLevel.light;
    case 'medium':
      return Anime4kLevel.medium;
    case 'high':
      return Anime4kLevel.high;
    default:
      return Anime4kLevel.off;
  }
}

/// `subprops=sub-ass:no|sub-pos:90` → {sub-ass: no, sub-pos: 90}
/// 只给 15 §A5 的四步排查用，正常播放路径不传这个参数。
Map<String, String> _parseSubProps(String? raw) {
  if (raw == null || raw.isEmpty) return const <String, String>{};
  final Map<String, String> out = <String, String>{};
  for (final String pair in raw.split('|')) {
    final int i = pair.indexOf(':');
    if (i <= 0) continue;
    out[pair.substring(0, i)] = pair.substring(i + 1);
  }
  return out;
}

/// 深链进房的落地页：拿到 code 就走 joinRoomAndEnter()，进房后直接替换成播放页。
/// 失败不白屏，给一句话人话 + 回首页按钮。
class JoinEntryPage extends StatefulWidget {
  const JoinEntryPage({
    super.key,
    required this.code,
    this.pwd = '',
    this.addr = '',
    this.from = JoinFrom.deeplink,
  });

  final String code;
  final String pwd;

  /// 分享链接带过来的房主地址；空串表示没带（照旧走通道探测）。
  final String addr;
  final JoinFrom from;

  @override
  State<JoinEntryPage> createState() => JoinEntryPageState();
}

class JoinEntryPageState extends State<JoinEntryPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (widget.code.isEmpty) {
      setState(() => _error = '房间码是空的');
      return;
    }
    try {
      debugPrint('[YQK-DEEPLINK] join code=${widget.code}');
      // 旧页面由 DeepLinkBridge 那一侧先弹干净（见 app.dart 的 _openRoomLink），
      // 这里只负责一件事：拿 code 进房（分享链接带了 addr 就一并交下去）。
      final bool entered = await joinRoomAndEnter(
        context,
        widget.code,
        from: widget.from,
        password: widget.pwd,
        addr: widget.addr,
      );
      // 没进成（满员/码不对/被踢）：toast 已经给过了，别把用户留在转圈页上
      if (!entered && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入房间')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('进不去房间：$_error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go(Routes.home),
                      child: const Text('回首页'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
