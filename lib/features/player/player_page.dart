import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, Platform;
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' show Dio;
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper, MediaStreamTrack;
import 'package:go_router/go_router.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../core/errors/failure_text.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/notify/notifier.dart';
import '../../core/utils/time_format.dart';
import '../../data/db/app_database.dart';
import '../../data/db/library_dao.dart';
import '../library/danmaku_library_page.dart';
import '../../data/download/download_engine.dart';
import '../../data/local/header_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../data/local/prefs.dart';
import '../../data/media/mkv_subtitle.dart';
import '../../domain/resolver.dart';
import '../../core/translate/translator_store.dart';
import '../../domain/translator.dart';
import '../../domain/danmaku_filter.dart';
import '../../domain/media_chapter.dart';
import '../../domain/chapter_skip.dart';
import '../../platform/player/anime4k.dart';
import '../../platform/player/kernel_factory.dart';
import '../../platform/player/playback_kernel.dart';
import '../../platform/room/room_client.dart';
import '../../platform/room/screen_share.dart';
import '../../platform/room/screen_engine.dart';
import '../../platform/room/voice_client.dart';
import '../../platform/room/voice_engine.dart';
import '../../platform/room/room_snapshot.dart';
import '../room/follow_rules.dart';
import '../room/room_overlay.dart';
import '../room/room_replay_page.dart';
import '../sources/sources_page.dart';
import 'danmaku_painter.dart';
import 'danmaku_send.dart';
import '../../domain/entities/room_message.dart';
import '../room/room_message_list.dart';
import '../../providers/app_providers.dart';
import '../../routing/routes.dart';
import '../../platform/player/mpv_kernel.dart';
import '../../platform/dlna/dlna_sender.dart';
import '../../platform/dlna/dlna_renderer.dart';
import '../../platform/dlna/local_media.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/app_theme.dart';
import '../../platform/player/subtitle_loader.dart';
import 'player_controller.dart';
import 'playlist_frame.dart';
import 'subtitle_overlay.dart';
import 'subtitle_scanner.dart';
import 'danmaku_overlay.dart';
import 'screen_view.dart';
import '../room/bot_config_page.dart';
import '../web/web_watch_page.dart';

/// P08 播放页（05 §3.2）。
///
/// 颜色只用 05 §1 的 token：播放页是唯一允许 videoBg/videoBar 深色的页面。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.media,
    this.startAt,
    this.controller,
    this.database,
    this.anime4k = Anime4kLevel.off,
    this.kernelKind,
    this.autoplay = true,
    this.holdAt,
    this.openAdvanced = false,
    this.autoExitAfter,
    this.audioTrack,
    this.subtitlePath,
    this.rateOverride,
    this.aspectIndex,
    this.audioFile,
    this.brightnessOverride,
    this.volumeOverride,
    this.subProps = const <String, String>{},
    this.roomClient,
    this.playlist = const <PlayerMedia>[],
  });

  final PlayerMedia media;
  final Duration? startAt;

  /// 测试注入用；正常走 [MpvKernel]
  final PlayerController? controller;
  final AppDatabase? database;

  /// 画质档位；Android 一律 off（04 §12.6.1）
  final Anime4kLevel anime4k;

  /// 指定内核；null 就用设置里的偏好（自动/mpv/fvp）
  final KernelKind? kernelKind;

  /// 打开后是否自动播（深链 autoplay=0 时停在首帧）
  final bool autoplay;

  /// 验收钩子：先播起来，再暂停并精确 seek 到这里，好让两次启动停在同帧
  final Duration? holdAt;

  /// 验收钩子（只在 debug 生效）：开播后自动打开高级面板，方便一次性截到属性表
  final bool openAdvanced;

  /// 验收钩子（只在 debug 生效）：播这么久之后自动退出播放页（用来验证还原亮度/音量）
  final Duration? autoExitAfter;

  /// 验收钩子（只在 debug 生效）：开播后自动切到第 N 条音轨
  final int? audioTrack;

  /// 验收钩子（只在 debug 生效）：开播后挂外挂字幕（本地路径）
  final String? subtitlePath;

  /// 验收钩子（只在 debug 生效）：开播后设倍速
  final double? rateOverride;

  /// 验收钩子（只在 debug 生效）：开播后设画面比例档位 0..3
  final int? aspectIndex;

  /// 验收钩子（只在 debug 生效）：开播后挂外挂音轨（本地路径）
  final String? audioFile;

  /// 验收钩子（只在 debug 生效）：开播后设应用亮度 0..1
  final double? brightnessOverride;

  /// 验收钩子（只在 debug 生效）：开播后设媒体音量 0..1
  final double? volumeOverride;

  /// 验收钩子（只在 debug 生效）：subprops=key:value|key:value，逐条写 mpv
  final Map<String, String> subProps;

  /// 房间客户端：非空时在播放页叠一层房间浮层（成员条/房主控制条/跟随条）
  final RoomClient? roomClient;

  /// 片单（同一部剧的剧集，M4 点进播放时带进来）：上一集/下一集/自动连播都靠它
  final List<PlayerMedia> playlist;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// 手势当前在改哪个东西
enum _DragMode { none, seek, brightness, volume }

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  /// 上一次打印的布局尺寸串（video/room/screen）；同值不重复打
  String? _lastLayoutKey;

  /// 上一次打印的「是不是房主」串；同值不重复打（_isRoomHost 每帧都会算）
  String? _hostLogKey;

  /// 房主已经点过允许/忽略的那条 claim 的 rid（本地先隐藏，不等服务端回包）
  String? _claimDismissedRid;

  /// I-57：客人侧被我们降级成「不本地连播」之前的原值；null = 没降级过。
  /// 退出播放页/变成房主时按它恢复，避免把用户的全局连播偏好永久改成关。
  bool? _autoNextBeforeDemote;

  /// I-57：上一次按角色下发 autoNext 的目标值；同值不重复写（状态帧两秒一次）
  bool? _autoNextRoleApplied;

  // P1b：隐藏时长统一 6 秒（原先 debug 30 秒 / release 3 秒，点完按钮还没看清就淡出）
  static const Duration _hideAfter = Duration(seconds: 6);
  static const Duration _fade = Duration(milliseconds: 200);

  /// 15 §A9：长按全屏 = 3 倍速（M2 任务口径）
  static const double _longPressRate = 3.0;

  /// 15 §A9：横向拖动，整屏宽度对应 180 秒
  static const double _seekSpanSeconds = 180;

  PlayerController? _controller;
  AppDatabase? _db;
  bool _ownsDb = false;

  // ── 收藏（F1：标题栏星标）──────────────────────────────
  bool _favOn = false;
  String _favUrl = '';

  /// 稍后看：和收藏共用 favorites 表，靠 tag='later' 区分
  bool _laterOn = false;
  bool _followOn = false;

  LibraryDao get _lib => LibraryDao(_db!);

  /// 已经扫过字幕的片子（同一次进播放页只扫一次）
  final Set<String> _subScanned = <String>{};

  static String _subId(String mediaUrl, String lang, String key) {
    final Digest d = md5.convert(utf8.encode('$mediaUrl|$lang|$key'));
    return d.toString().substring(0, 16);
  }

  /// F12：本地片子开播后扫同目录字幕，扫到就写库（只扫目录，不递归）
  Future<void> _scanSubtitlesOnce(PlayerMedia m) async {
    final String url = m.url;
    if (_subScanned.contains(url)) return;
    // 本地文件、以及本机媒体库的 /local/media/play?path=… 都算本地片子
    final String? path = SubtitleScanner.videoPathOf(url);
    if (path == null) return;
    _subScanned.add(url);
    final AppDatabase? db = _db;
    if (db == null) return;
    final List<ScannedSubtitle> found =
        await const SubtitleScanner().scan(path);
    for (final ScannedSubtitle s in found) {
      await db.subtitleDao.upsert(SubtitlesCompanion.insert(
        id: _subId(url, s.lang, s.path),
        mediaUrl: url,
        label: s.label,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        lang: Value<String>(s.lang),
        path: Value<String?>(s.path),
        format: Value<String>(s.format),
      ));
    }
    debugPrint('[YQK-SUB] scan stored n=${found.length} url=$url');
  }

  /// 把库里的字幕挂上（本地路径直接喂；在线地址先下到临时目录）
  Future<void> _applySubtitleRow(PlayerController c, SubtitleRow row) async {
    String? local = row.path;
    if ((local == null || local.isEmpty) && row.url != null) {
      final String target =
          '${Directory.systemTemp.path}/yqk_sub_${row.id}.${row.format}';
      await Dio().download(row.url!, target);
      local = target;
      debugPrint('[YQK-SUB] fetch url=${row.url} -> $target');
    }
    if (local == null || local.isEmpty) return;
    await c.setSubtitle(local, label: row.label);
    await _loadSubtitleData(local);
    await _db?.subtitleDao.setLastUsed(row.id);
    debugPrint('[YQK-SUB] apply id=${row.id} label=${row.label} path=$local');
  }

  Future<void> _loadFav() async {
    final AppDatabase? db = _db;
    if (db == null) return;
    final PlayerMedia m = _controller?.media ?? widget.media;
    final bool on = await LibraryDao(db).isFavorite(m.url);
    debugPrint('[YQK-FAV] load url=${m.url} on=$on prev=$_favUrl');
    if (!mounted) return;
    setState(() {
      _favOn = on;
      _favUrl = m.url;
    });
  }

  Future<void> _toggleFav() async {
    final PlayerMedia m = _controller?.media ?? widget.media;
    final bool on = await _lib.toggleFavorite(LibraryMedia(
      title: m.title,
      url: m.url,
      sourceKind: m.sourceKind,
      sourceId: m.sourceId,
      poster: m.poster,
      episodeIndex: m.episodeIndex,
    ));
    debugPrint('[YQK-FAV] toggle url=${m.url} on=$on');
    if (!mounted) return;
    setState(() {
      _favOn = on;
      _favUrl = m.url;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? '已收藏' : '已取消')),
    );
  }

  /// 稍后看：tag='later'；星标与它共用 favorites 表，listFavorites 过滤 tag!=later，不会串。
  Future<void> _loadLater() async {
    final AppDatabase? db = _db;
    if (db == null) return;
    final PlayerMedia m = _controller?.media ?? widget.media;
    final List<Favorite> later = await LibraryDao(db).listWatchLater();
    final bool on = later.any((Favorite f) => f.url == m.url);
    if (!mounted) return;
    setState(() => _laterOn = on);
  }

  Future<void> _toggleLater() async {
    final PlayerMedia m = _controller?.media ?? widget.media;
    final bool on = await _lib.markWatchLater(LibraryMedia(
      title: m.title,
      url: m.url,
      sourceKind: m.sourceKind,
      sourceId: m.sourceId,
      poster: m.poster,
      episodeIndex: m.episodeIndex,
    ));
    debugPrint('[YQK-FAV] later on=$on url=${m.url}');
    if (!mounted) return;
    setState(() => _laterOn = on);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? '已加入稍后看' : '已移出稍后看')),
    );
  }

  /// 追番：tag='follow'（单值语义：收藏 + 追番时以追番为准）
  Future<void> _loadFollow() async {
    final AppDatabase? db = _db;
    if (db == null) return;
    final PlayerMedia m = _controller?.media ?? widget.media;
    final bool on = await LibraryDao(db).isFollowing(m.url);
    if (!mounted) return;
    setState(() => _followOn = on);
  }

  Future<void> _toggleFollow() async {
    final PlayerMedia m = _controller?.media ?? widget.media;
    final bool on = await _lib.markFollow(LibraryMedia(
      title: m.title,
      url: m.url,
      sourceKind: m.sourceKind,
      sourceId: m.sourceId,
      poster: m.poster,
      episodeIndex: m.episodeIndex,
    ));
    debugPrint('[YQK-FAV] follow on=$on url=${m.url}');
    if (!mounted) return;
    setState(() {
      _followOn = on;
      if (on) _favOn = true; // 追番同时算收藏（同一行）
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? '已开始追番' : '已取消追番')),
    );
  }

  /// 下载本片：立刻入队，重复点同 url 提示已在队列
  Future<void> _downloadThis() async {
    final PlayerMedia m = _controller?.media ?? widget.media;
    final String url = m.url;
    // 本机 file:// 片子没有下载的意义（也不支持），直接拦掉
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _snack('本机文件不用下载');
      debugPrint('[YQK-DL] skip local url=$url');
      return;
    }
    final bool ok =
        await DownloadEngine.instance.enqueue(url: url, title: m.title);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已加入下载队列' : '已在下载队列')),
    );
  }
  StreamSubscription<String>? _noticeSub;
  /// I-44：被踢 / 房间关了 → 回首页。只处理一次，避免 dispose 时的 closed 再弹一次。
  StreamSubscription<RoomClientState>? _stateSub;
  bool _closedHandled = false;

  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  String? _openError;

  // 手势状态
  _DragMode _mode = _DragMode.none;
  Offset _dragStart = Offset.zero;
  Duration? _seekPreview;
  double? _brightnessPreview;
  double? _volumePreview;

  // 原值：退出播放页必须还原（硬要求）
  double? _originalBrightness;
  double? _originalVolume;

  /// 外挂字幕的解析结果（Flutter 层自绘用；mpv 那边仍然照挂，两者不冲突）
  SubtitleData? _subData;
  bool _brightnessIsApplicationLevel = false;
  double _rateBeforeLongPress = 1.0;

  /// D22：一起看网页。房主本地打开后广播 `open`，客人收到就自己弹同一个页面。
  StreamSubscription<Map<String, dynamic>>? _webSub;
  bool _webOpen = false;

  /// D20（第一步）：屏幕采集器。只在房主菜单里手动开关，不推流、不发任何 room 帧。
  ScreenShare? _screen;

  /// D12：片尾只触发一次 next。内核 completed 事件是每集一次，拖回片中要复位，
  /// 否则手动拖回片头再看到结尾就不再切集了。
  bool _endedFired = false;

  // ── H4：章节 / 片头片尾 ─────────────────────────────────
  /// 片源自带的章节（进片时读一次，空表 = 没有章节）
  List<MediaChapter> _chapters = const <MediaChapter>[];

  /// 同一片只跳一次片头的内存标记（切片/换片复位）
  final ChapterSkip _chapSkip = ChapterSkip();

  /// 手动标记（库里一行，-1 = 未设）
  ChapterMark? _chapMark;

  /// 两个开关默认关（自动跳会让用户懵）
  bool _skipIntro = false;
  bool _skipOutro = false;
  /// 上一次切片后的片单下标。ended 时若控制器自己的 autoNext 已经前进过，
  /// 这个值会比当前下标小 —— 用来区分「真切集」和「最后一集播完」（后者不能补 play，
  /// 否则会 0 秒循环重播最后一集）。
  int _lastPlIndex = -1;
  StreamSubscription<PlaybackEvent>? _endedSub;
  Object? _endedKernelRef;

  /// G9：已提醒过的成员 id（房主后台时新成员进房只提醒一次）
  final Set<String> _seenMembers = <String>{};

  bool _amHostNow() {
    final RoomClient? rc = widget.roomClient;
    final String? id = rc?.memberId;
    if (rc == null || id == null) return false;
    return rc.snapshot.value?.memberById(id)?.isOwner ?? false;
  }

  void _onWebEvent(Map<String, dynamic> w) {
    final String action = (w['action'] ?? '').toString();
    if (action != 'open') return;
    if (_amHostNow() || _webOpen || !mounted) return;
    final String u = (w['url'] ?? '').toString();
    if (u.isEmpty) return;
    debugPrint('[YQK-WEB] open url=$u by-host=false（跟随）');
    unawaited(_openWebWatch(initialUrl: u));
  }

  /// 客人侧收到房主换片源的 media 帧：换成同一部片，不再回发。
  void _onMediaFrame() {
    final RoomClient? rc = widget.roomClient;
    final Map<String, dynamic>? f = rc?.mediaFrame.value;
    if (rc == null || f == null) return;
    rc.clearMediaFrame();
    final String url = (f['url'] ?? '').toString();
    if (url.isEmpty) return;
    final PlayerMedia m = PlayerMedia(
      id: (f['id'] ?? url).toString(),
      title: (f['title'] ?? '房间片源').toString(),
      url: url,
      sourceKind: (f['sourceKind'] ?? 'room').toString(),
      sourceId: f['sourceId']?.toString(),
      poster: (f['poster'] as String?)?.isEmpty ?? true
          ? null
          : f['poster'] as String,
    );
    // 第 38 轮：房主会把整条线路的片单一起带过来（urls/titles）。
    // 必须先 setPlaylist 再 open —— open 内部按 media.id 在片单里定位当前集，
    // 顺序反了 index 会算错（-1），hasNext 也就永远 false。
    final PlayerController? c = _controller;
    final List<PlayerMedia> pl = playlistFromMediaFrame(f);
    if (c != null && pl.isNotEmpty) c.setPlaylist(pl, currentId: url);
    debugPrint('[YQK-MEDIA] switch guest url=$url title=${m.title} '
        'playlist=${c?.playlistLength ?? 0} idx=${c?.playlistIndex ?? -1}');
    unawaited(_switchMedia(m, broadcast: false));
  }

  /// 换片源：房主选片后整房切过去；客人只跟随（broadcast=false）。
  Future<void> _switchMedia(PlayerMedia m, {required bool broadcast}) async {
    final PlayerController? c = _controller;
    if (c == null) return;
    // 切片先把上一条的进度落盘（open 内部也会 flush，这里多一层保险）
    await c.open(m);
    // 同一个内核上二次 open 时 FVP 会停在 PlaybackState.stopped（实测房主黑屏），
    // 这里显式补一次 play()；首次 open 已经自动播时 playing 为 true，不会重复调用。
    if (!c.playing) {
      try {
        await c.play();
      } on Object catch (err) {
        debugPrint('[YQK-MEDIA] 切片后补 play 失败：$err');
      }
    }
    // 新片从头开始，上一次的「已播完」标记要清掉，否则 D12 的自动连播不再触发
    _endedFired = false;
    // H4：换片要重读章节/标记，并复位「本片已跳过片头」
    _chapSkip.reset();
    unawaited(_loadChapters(c));
    // 记下这次切到的片单下标：ended 时用它判断控制器有没有自己前进过
    _lastPlIndex = c.playlistIndex;
    if (broadcast) {
      final RoomClient? rc = widget.roomClient;
      // 片单随帧带走（最多 50 条，整季几百集不能全塞进帧里）
      final List<PlayerMedia> pl = c.playlist;
      final int cap = pl.length > 50 ? 50 : pl.length;
      final List<PlayerMedia> head = pl.take(cap).toList();
      debugPrint('[YQK-MEDIA] switch host url=${m.url} title=${m.title} '
          'playlist=${c.playlistLength} idx=${c.playlistIndex}');
      rc?.send(<String, dynamic>{
        'type': 'media',
        'url': m.url,
        'title': m.title,
        'poster': m.poster ?? '',
        'sourceKind': m.sourceKind,
        'sourceId': m.sourceId ?? '',
        'urls': head.map((PlayerMedia e) => e.url).toList(),
        'titles': head.map((PlayerMedia e) => e.title).toList(),
      });
      // 房间权威状态里的片源也一起换，重连/后进房的人拿到的是新片
      // 注意：这里不再补发 state —— auth 帧由播放器自己的 play/pause 状态机发，
      // 额外塞一条 position=0 的 state 会把房主本地刚打开的片子打成 stopped（实测黑屏）。
    }
  }

  /// 房主菜单「换片源」：进片源页的选片模式，选中后整房切片。
  ///
  /// 第 38 轮：片源页回传的是 `{'media': PlayerMedia, 'playlist': List<PlayerMedia>}`，
  /// 片单必须先灌进 controller（`setPlaylist`）再切片 —— `open()` 靠片单定位当前集，
  /// 顺序反了 `playlistIndex` 会停在 -1，D12 的 ended 就永远走「跳过」。
  Future<void> _pickMediaForRoom() async {
    if (!_amHostNow()) return;
    final Map<String, Object?>? picked = await Navigator.of(context)
        .push<Map<String, Object?>>(MaterialPageRoute<Map<String, Object?>>(
      builder: (_) => const SourcesPage(pickMode: true),
    ));
    if (picked == null || !mounted) return;
    final PlayerMedia? media = picked['media'] as PlayerMedia?;
    if (media == null) return;
    final List<PlayerMedia> pl =
        (picked['playlist'] as List<PlayerMedia>?) ?? const <PlayerMedia>[];
    final PlayerController? c = _controller;
    if (c != null && pl.isNotEmpty) {
      c.setPlaylist(pl, currentId: media.id);
    }
    await _switchMedia(media, broadcast: true);
  }

  /// M10 C 组：房主房间内把本机变成「可被投屏的设备」。
  ///
  /// Java 侧 DlnaRenderer 负责 SSDP 应答 + SOAP 解析，命令排队；这里只负责
  /// 起停和把命令作用到当前播放器。退房/离页在 dispose 里 stop()。
  Future<void> _startDlnaBridge() async {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return;
    if (!_amHostNow()) {
      debugPrint('[YQK-DLNA] renderer skip not-host');
      return;
    }
    final String name = '一起看 ${rc.roomCode}';
    final DlnaRendererBridge bridge = DlnaRendererBridge(
      base: 'http://127.0.0.1:8080',
      onLog: debugPrint,
      onCommand: _onDlnaCommand,
    );
    _dlnaBridge = bridge;
    await bridge.start(name);
    debugPrint('[YQK-DLNA] bridge ready name=$name');
  }

  /// 收到一条 DLNA 命令，作用到当前播放器。
  void _onDlnaCommand(Map<String, dynamic> cmd) {
    final String name = '${cmd['cmd'] ?? ''}';
    final PlayerController? c = _controller;
    if (c == null) return;
    switch (name) {
      case 'SetAVTransportURI':
        final String url = '${cmd['url'] ?? ''}';
        if (url.isEmpty) return;
        debugPrint('[YQK-DLNA] set uri=$url → play');
        unawaited(_switchMedia(
          PlayerMedia(
            id: 'dlna_${DateTime.now().millisecondsSinceEpoch}',
            title: _guessName(url),
            url: url,
            sourceKind: 'dlna',
          ),
          broadcast: _amHostNow(),
        ));
      case 'Play':
        unawaited(c.play());
        debugPrint('[YQK-DLNA] apply Play');
      case 'Pause':
        unawaited(c.pause());
        debugPrint('[YQK-DLNA] apply Pause');
      case 'Stop':
        unawaited(c.pause());
        unawaited(c.seek(Duration.zero));
        debugPrint('[YQK-DLNA] apply Stop');
      case 'Seek':
        final double sec = DlnaRendererBridge.asSeconds(cmd['pos']);
        unawaited(c.seek(Duration(milliseconds: (sec * 1000).round())));
        debugPrint('[YQK-DLNA] apply Seek pos=$sec');
      default:
        debugPrint('[YQK-DLNA] ignore cmd=$name');
    }
  }

  String _guessName(String url) {
    final Uri? u = Uri.tryParse(url);
    final String last = (u?.pathSegments.isNotEmpty ?? false) ? u!.pathSegments.last : url;
    return last.isEmpty ? '投屏内容' : last;
  }

  /// M10 B 组：⋯ 菜单「投到电视」。搜索 MediaRenderer，选中后把当前片子投过去。
  Future<void> _castToDlna() async {
    final String url = widget.media.url;
    if (url.isEmpty) {
      _snack('当前没有可投的片子');
      return;
    }
    _snack('正在搜索可投屏的设备…');
    final List<DlnaDevice> devices = await ssdpDiscover(onLog: debugPrint);
    if (!mounted) return;
    if (devices.isEmpty) {
      _snack('没找到可投屏的设备，确认电视和手机在同一个 Wi-Fi');
      return;
    }
    final DlnaDevice? picked = await showModalBottomSheet<DlnaDevice>(
      context: context,
      backgroundColor: const Color(0xFF14161B),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('投到电视',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final DlnaDevice d in devices)
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(d.friendlyName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(d.modelName, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(ctx).pop(d),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await DlnaSender(picked).play(url, title: widget.media.title);
      _castDevice = DlnaSender(picked);
      _castLastPos = _controller?.position ?? Duration.zero;
      _castLastPlaying = _controller?.playing ?? false;
      debugPrint('[YQK-DLNA] cast ok device=${picked.friendlyName} url=$url '
          'follow=true pos=${_castLastPos.inSeconds}s');
      _snack('已投到 ${picked.friendlyName}');
    } catch (e) {
      debugPrint('[YQK-DLNA] cast fail device=${picked.friendlyName} err=$e');
      _snack('投屏失败：$e');
    }
  }

  /// M13 H11：打开本房间回放。数据在房主手机内存里（`/local/replay`），
  /// 只覆盖「本场房间」这段时间的记录。
  void _openRoomReplay() {
    final RoomClient? rc = widget.roomClient;
    final String code = rc?.roomCode ?? '';
    if (code.isEmpty) {
      _snack('不在房间里，没有回放');
      debugPrint('[YQK-REC] open skip not-in-room');
      return;
    }
    debugPrint('[YQK-REC] open code=$code');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomReplayPage(
          code: code,
          replayUrl: 'http://127.0.0.1:8080',
          onSeek: _seekFromReplay,
        ),
      ),
    );
  }

  /// 回放条目点一下就跳到当时的进度。只有「同一条 url」才跳 —— 跨片子跳
  /// 会把人弄懵，所以给个提示让用户自己打开那条。
  void _seekFromReplay(double seconds, String? mediaUrl) {
    final PlayerController? c = _controller;
    final String nowUrl = c?.media?.url ?? widget.media?.url ?? '';
    if (mediaUrl != null && mediaUrl.isNotEmpty && mediaUrl != nowUrl) {
      debugPrint('[YQK-REC] seek miss url=$mediaUrl now=$nowUrl');
      _snack('这一条属于别的片子：请先打开它');
      return;
    }
    c?.seek(Duration(milliseconds: (seconds * 1000).round()));
    debugPrint('[YQK-REC] seek pos=${seconds.toStringAsFixed(1)} url=$nowUrl');
    Navigator.of(context).maybePop();
  }

  /// M10 D 组：⋯ 菜单「本机视频」。先要权限，再列 /sdcard/Movies，选中即播。
  Future<void> _openLocalMedia() async {
    Permission perm = Permission.videos;
    if (!await perm.isGranted) {
      final PermissionStatus stt = await perm.request();
      if (!stt.isGranted) {
        // Android 12 及以下没有「视频」这个分组，退回「存储」
        perm = Permission.storage;
        if (!await perm.isGranted) {
          final PermissionStatus st2 = await perm.request();
          if (!st2.isGranted) {
            debugPrint('[YQK-MEDIA] permission denied perm=$perm status=$st2');
            if (mounted) _snack('没有读取权限，去设置里开启');
            return;
          }
        }
      }
    }
    const String base = 'http://127.0.0.1:8080';
    final LocalMediaResult res = await LocalMediaClient(base).list();
    debugPrint('[YQK-MEDIA] list path=${res.path} ok=${res.ok} n=${res.items.length} '
        'detail=${res.detail}');
    if (!mounted) return;
    if (!res.ok) {
      _snack(res.detail.contains('permission')
          ? '没有读取权限，去设置里开启'
          : '列目录失败：${res.detail}');
      return;
    }
    if (res.items.isEmpty) {
      _snack('${res.path} 里没有视频文件');
      return;
    }
    final LocalMediaItem? picked = await showModalBottomSheet<LocalMediaItem>(
      context: context,
      backgroundColor: const Color(0xFF14161B),
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('本机视频 · ${res.path}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final LocalMediaItem it in res.items)
              ListTile(
                leading: const Icon(Icons.movie_outlined),
                title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(it.sizeText),
                onTap: () => Navigator.of(ctx).pop(it),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final String url = LocalMediaClient(base).playUrl(picked.path);
    debugPrint('[YQK-MEDIA] open path=${picked.path} url=$url');
    await _switchMedia(
      PlayerMedia(
        id: 'local_${picked.path.hashCode}',
        title: picked.name,
        url: url,
        sourceKind: 'local',
      ),
      broadcast: _amHostNow(),
    );
  }

  /// D20 第一步：开/关屏幕采集。
  ///
  /// 只在本机起 MediaProjection 采集（拿到一条视频轨就够），不推流、不进房间、
  /// 不发任何 WS 帧；目的是先确认 targetSdk=36 下授权链和真实参数。
  Future<void> _toggleScreenShare() async {
    if (_screen == null) {
      _screen = ScreenShare(onLog: debugPrint);
      final bool ok = await _startScreenShare();
      if (!mounted) return;
      // 起不来就把句柄丢掉：否则菜单会一直显示「停止共享」，
      // 用户得先点一次停止才能再试（实测 19:30:58 就是这种两下才生效）。
      if (!ok) _screen = null;
      if (ok) {
        // D20 第二步：把这条轨推给房间里每个在线成员（本轮只跑信令，不渲染）。
        final RoomClient? rc = widget.roomClient;
        final MediaStreamTrack? track = _screen?.screenTrack;
        if (rc != null && track != null) {
          final List<String> peers = _roomClientPeerIds(rc);
          debugPrint('[YQK-SCREEN] broadcast peers=${peers.length}');
          if (peers.isNotEmpty) {
            await _screenEngine(rc).start(
              track,
              peers,
              audioTracks: _screen?.audioTracks ?? const <MediaStreamTrack>[],
            );
          }
        }
        // 房主自己也看一眼：本地预览直接用 screenTrack，不走 onRemoteTrack。
        if (track != null && mounted) {
          setState(() => _remoteScreen = track);
        }
      }
      _snack(ok
          ? '屏幕共享已开始'
          : '屏幕共享没起来：第一次用需要先授权一次，再点一次「共享屏幕」');
      setState(() {});
    } else {
      await _screenEngineOrNull?.stop();
      _screenEngineOrNull = null;
      await _screen!.stop();
      _screen = null;
      if (mounted) {
        setState(() => _remoteScreen = null);
        _snack('屏幕共享已停止');
        setState(() {});
      }
    }
  }

  /// 真正去要权限并起采集；失败已在 ScreenShare 内部打日志并 return false。
  Future<bool> _startScreenShare() async {
    final ScreenShare? s = _screen;
    if (s == null) return false;
    final bool ok = await s.start();
    debugPrint('[YQK-SCREEN] share on tracks=${s.trackCount}');
    return ok;
  }

  Future<void> _openWebWatch({String? initialUrl}) async {
    final RoomClient? rc = widget.roomClient;
    if (rc == null || _webOpen) return;
    _webOpen = true;
    // 进来就把播放器停在原地：网页是房间里的一个页面，不是盖在播放器上的浮层
    unawaited(_controller?.pause());
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WebWatchPage(
          roomClient: rc,
          isHost: _amHostNow(),
          initialUrl: initialUrl,
        ),
      ));
    } finally {
      _webOpen = false;
    }
  }

  /// 当前连接是不是房主：只读快照，不发请求。决定控制条是否渲染、跟随条挂多高。
  bool _isRoomHost(PlayerController c) {
    final RoomClient? rc = widget.roomClient;
    final String? id = rc?.memberId;
    if (rc == null || id == null) return false;
    final bool v = rc.snapshot.value?.memberById(id)?.isOwner ?? false;
    final String k = '$v|$id|${rc.snapshot.value?.members.length}';
    if (k != _hostLogKey) {
      _hostLogKey = k;
      debugPrint('[YQK-CLAIM] isHost=$v me=$id members=${rc.snapshot.value?.memberCount ?? -1}');
    }
    return v;
  }

  /// I-57：客人侧关掉「本地自动连播」。
  ///
  /// 客人的片单是房主随 media 帧带过来的同一份，客人自己在结尾自动 advance 会跟
  /// 房主的 next 帧抢——两边各切一次，快进一集。所以客人只跟房主帧走，本地连播关掉。
  /// 房主保持自己的设置不动（不能因为当房主就把用户关掉的连播又打开）。
  void _applyAutoNextForRole(PlayerController c) {
    final bool host = _isRoomHost(c);
    // 目标状态：房主 = 恢复原值（没降级过就不动）；客人 = false
    if (host == _autoNextRoleApplied) return;
    _autoNextRoleApplied = host;
    if (host) {
      final bool? before = _autoNextBeforeDemote;
      _autoNextBeforeDemote = null;
      if (before != null && before != c.autoNext) {
        unawaited(c.setAutoNext(before));
      }
    } else {
      _autoNextBeforeDemote ??= c.autoNext;
      if (c.autoNext) unawaited(c.setAutoNext(false));
    }
    debugPrint('[YQK-AUTONEXT] room=$host autoNext=${host ? c.autoNext : false}');
  }

  /// 快照变了（成员表/房主变了）才重新算一次角色，别每帧都写 pref
  void _onSnapshotForAutoNext() {
    final PlayerController? c = _controller;
    if (c != null) _applyAutoNextForRole(c);
    _maybeNotifyRoomJoin();
  }

  /// G9：房主在后台时有人进房 → 弹一条「进入房间」通知。
  ///
  /// 我们没有「进房审批队列」（showRoomInvite 的原始设想），所以触发点选
  /// 「房主 + App 在后台 + 成员表里出现了没见过的 guest」。同一成员只提醒一次。
  void _maybeNotifyRoomJoin() {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return;
    final RoomSnapshot? s = rc.snapshot.value;
    if (s == null || !_amHostNow()) return;
    final List<RoomMember> guests = s.members
        .where((RoomMember m) => !m.isOwner)
        .toList(growable: false);
    if (guests.isEmpty) return;
    final Set<String> ids = guests.map((RoomMember m) => m.id).toSet();
    final bool bg = WidgetsBinding.instance.lifecycleState ==
        AppLifecycleState.paused;
    for (final RoomMember m in guests) {
      if (_seenMembers.contains(m.id)) continue;
      _seenMembers.add(m.id);
      if (!bg) continue;
      unawaited(AppNotifier.instance
          .showRoomInvite(rc.roomCode, m.nickname.isEmpty ? '有人' : m.nickname));
      debugPrint('[YQK-NOTIFY] room invite code=${rc.roomCode} member=${m.id}');
    }
    _seenMembers.removeWhere((String id) => !ids.contains(id));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // G9：通知栏的 prev / toggle / next 落到当前播放页
    PlayerRemote.onAction = _onRemoteAction;
    unawaited(_loadDanmakuSettings());
    final RoomClient? rc0 = widget.roomClient;
    if (rc0 != null) {
      _bindVoiceNotice(rc0);
      _bindVoicePeers(rc0);
      _bindP2P(rc0);
    }
    unawaited(_boot());
    unawaited(_startDlnaBridge());
    unawaited(_loadFav());
    unawaited(_loadLater());
    unawaited(_loadFollow());
    unawaited(_loadTranslator());
  }

  /// H2：翻译器（没配置就是 NoopTranslator，菜单里不显示「翻译」）
  Translator _translator = const NoopTranslator();

  Future<void> _loadTranslator() async {
    final Translator tr = await TranslatorStore().load();
    if (!mounted) return;
    setState(() => _translator = tr);
    debugPrint('[YQK-TRANS] load configured=${tr.isConfigured}');
  }

  /// 弹幕显示设置（本地偏好）：进页面先读一次，再让 UI 用
  DanmakuSettings _dm = const DanmakuSettings();

  Future<void> _loadDanmakuSettings() async {
    final DanmakuSettings s = await DanmakuSettings.load();
    if (!mounted) return;
    setState(() => _dm = s);
    debugPrint('[YQK-DM] 设置恢复 visible=${s.visible} opacity=${s.opacity} '
        'speed=${s.speed} font=${s.fontSize}');
  }

  Future<void> _saveDanmakuSettings() async {
    await _dm.save();
    debugPrint('[YQK-DM] 设置保存 visible=${_dm.visible} opacity=${_dm.opacity} '
        'speed=${_dm.speed} font=${_dm.fontSize}');
  }

  /// debug 专用：用播放器当前位置发一条弹幕。
  ///
  /// 用途：验证「drawn>0 且位置对齐」——外部队列按服务端 /api 的位置发包会滞后
  /// 3-5 秒（服务端只在 2 秒心跳里更新 position），落到绘制窗口外面就一条都不画。
  /// 这里直接读 PlayerController.position（与弹幕层同一个真源），位置天然对齐。
  /// 只在 kDebugMode 下由 ⋯ 菜单调用，不影响任何上报路径。
  void _sendDebugDanmaku() {
    final PlayerController? c = _controller;
    final RoomClient? rc = widget.roomClient;
    if (c == null || rc == null) return;
    final double pos = c.position.inMilliseconds / 1000.0;
    // 一次发 3 条、pos 依次 +0.6 秒：三条铺在同一条时间轴上，过 1.6 秒后
    // 正好分别停在 x≈24 / 96 / 168，都在屏内且互不重叠，方便一次截图取证。
    for (int i = 0; i < 3; i++) {
      final double p = double.parse((pos + i * 0.6).toStringAsFixed(2));
      final String text = '调试弹幕 ${i + 1}';
      rc.send(<String, dynamic>{
        'type': 'danmaku',
        'text': text,
        'pos': p,
        'color': 16777215,
        'mode': 'scroll',
        'size': 1.0,
        'bold': false,
      });
      // 服务端 relay 跳过发送者，自己发的帧不会回来；这里本地回显，才能「点完立刻看到」。
      rc.debugInjectDanmaku(RoomDanmaku(
        id: 'dbg_${DateTime.now().microsecondsSinceEpoch}_$i',
        from: rc.memberId ?? '',
        name: '我',
        text: text,
        pos: p,
        at: DateTime.now().millisecondsSinceEpoch,
        color: 16777215,
        mode: 'scroll',
        size: 1.0,
      ));
    }
    debugPrint('[YQK-DM] debug send pos=${pos.toStringAsFixed(2)} ×3');
    // 取证需要：立刻收起控制层，否则标题/进度条/中央按钮会压住弹幕。
    // 只是把 _controlsVisible 置 false，播放状态与上报路径都不动。
    _hideTimer?.cancel();
    if (_controlsVisible) setState(() => _controlsVisible = false);
  }

  /// 发一条聊天；如果弹幕开关开着，同时发一条同文弹幕并本地回显。
  ///
  /// pos 取「按下发送这一刻」的 `c.position` —— 不是录制时的时间，也不是
  /// 服务端 `state.position`（每 2 秒上报一次，会滞后几十秒，M8 实踩）。
  /// 帧字段与回显用同一个 Duration，保证自己和别人在同一条时间轴上。
  void _sendChat(String text) {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return;
    // 被禁言就别发也别回显：服务端会拒（errObj("muted")），但本地回显先跑，
    // 结果是自己看得见、别人看不见，比「发不出去」更让人困惑。
    if (amMuted(rc.snapshot.value, rc.memberId)) {
      _snack('你被禁言了');
      debugPrint('[YQK-CHAT] send blocked muted');
      return;
    }
    final String chId = 'ch_${DateTime.now().microsecondsSinceEpoch}';
    rc.send(<String, dynamic>{
      'type': 'chat',
      'kind': 'text',
      'text': text,
      'id': chId,
    });
    // 服务端 relay 跳过发送者，自己的话不会从 WS 回来 —— 本地回显一条，
    // 否则说话人自己的气泡永远不出现（M8 实测：只有对方能看到）。
    // I-46：回显 id 与发出去的 id 必须一致，否则同一条会显示两个气泡。
    rc.injectLocalChat(ChatMessage(
      id: chId,
      from: rc.memberId ?? '',
      name: '我',
      kind: 'text',
      text: text,
      at: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!_dm.sendEnabled) {
      debugPrint('[YQK-DM] send skip danmaku (switch off) text=${text.length}字');
      return;
    }
    final PlayerController? c = _controller;
    // 没有控制器（片源还没起来）就只发聊天：没有可信的 pos，宁可不发，
    // 也不要拿 0 或服务端旧 pos 凑一条位置错的弹幕。
    if (c == null) {
      debugPrint('[YQK-DM] send skip danmaku (no controller)');
      return;
    }
    final Duration pos = c.position;
    final String dmId = 'dm_${DateTime.now().microsecondsSinceEpoch}';
    rc.send(buildDanmakuFrame(id: dmId, text: text, position: pos));
    rc.debugInjectDanmaku(buildLocalEchoDanmaku(
      text: text,
      position: pos,
      id: dmId,
      from: rc.memberId ?? '',
    ));
    debugPrint('[YQK-DM] send pos=${(pos.inMilliseconds / 1000.0).toStringAsFixed(2)} '
        'text=${text.length}字');
    // 刚发的那条要能看清：控制层（标题栏 / ⏪⏸⏩ / 进度条）在 202.5 高的竖屏视频上
    // 盖住 28%–91%，弹幕 21%–61% 的安全区整个落在它里面。和调试入口同一处理：
    // 只置 _controlsVisible=false，不碰播放状态与上报。
    _hideTimer?.cancel();
    if (_controlsVisible) setState(() => _controlsVisible = false);
  }

  /// 点麦克风：加入 / 已在语音则什么都不做（退出走长按）。
  ///
  /// 不在房间（roomClient 为空）时只提示，不发帧 —— V6 那条：
  /// 没有房间就没有成员身份，服务端只会回 no-room，不如本地就说清楚。
  void _toggleVoice() {
    unawaited(_joinVoice());
  }

  /// 进语音：先要权限、再采本地音轨，都成功了才发 voice{action:join}。
  /// 顺序不能反 —— 没权限就 join，等于给别人一个哑巴成员。
  Future<void> _joinVoice() async {
    final RoomClient? rc = widget.roomClient;
    if (rc == null || rc.roomCode.isEmpty) {
      debugPrint('[YQK-VOICE] join blocked not-in-room');
      _snack('先进房间');
      return;
    }
    final VoiceState vs = rc.voiceState.value;
    if (vs.joined) {
      debugPrint('[YQK-VOICE] tap 但已在语音，忽略（长按退出）');
      return;
    }
    if (vs.length >= kVoiceMax) {
      debugPrint('[YQK-VOICE] full 拒绝加入 members=${vs.length}');
      _snack('语音房已满（最多 $kVoiceMax 人）');
      return;
    }
    final VoiceEngine engine = _voiceEngine(rc);
    final bool ok = await engine.start(rc.memberId ?? '');
    if (!ok) {
      debugPrint('[YQK-VOICE] mic denied 回滚，不发 join');
      _snack('需要麦克风权限');
      await engine.stop();
      return;
    }
    await _duckForVoice();
    rc.sendVoiceJoin();
    debugPrint('[YQK-VOICE] join send members=${vs.length}');
  }

  /// 长按麦克风：退出语音。不在语音里就不发帧。
  void _leaveVoice() {
    unawaited(_leaveVoiceAsync());
  }

  Future<void> _leaveVoiceAsync() async {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return;
    if (!rc.voiceState.value.joined) return;
    rc.sendVoiceLeave();
    debugPrint('[YQK-VOICE] leave send');
    await _unduckVoice();
    await _voiceEngineOrNull?.stop();
  }

  /// 把播放器音量压到 30 再放出来。用 mpv 的 volume 属性，
  /// 不碰 VolumeController（那是系统音量，会把用户其他 App 一起压低）。
  Future<void> _duckForVoice() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    try {
      final String? v0 = await c.kernel.readProperty('volume');
      _duckPrev = v0 ?? '100';
      await c.kernel.setProperty('volume', '30');
      debugPrint('[YQK-VOICE] duck $_duckPrev -> 30');
    } catch (e) {
      debugPrint('[YQK-VOICE] duck fail ${e.runtimeType}');
    }
    try {
      await Helper.setSpeakerphoneOn(true);
      debugPrint('[YQK-VOICE] speaker on');
    } catch (e) {
      debugPrint('[YQK-VOICE] speaker fail ${e.runtimeType}');
    }
  }

  Future<void> _unduckVoice() async {
    final PlayerController? c = _controller;
    if (c != null) {
      try {
        await c.kernel.setProperty('volume', _duckPrev ?? '100');
        debugPrint('[YQK-VOICE] duck restore -> ${_duckPrev ?? '100'}');
      } catch (e) {
        debugPrint('[YQK-VOICE] duck restore fail ${e.runtimeType}');
      }
    }
    try {
      await Helper.setSpeakerphoneOn(false);
      debugPrint('[YQK-VOICE] speaker off');
    } catch (e) {
      debugPrint('[YQK-VOICE] speaker off fail ${e.runtimeType}');
    }
  }

  VoiceEngine? _voiceEngineOrNull;

  /// 进语音前的 mpv 音量原值（'100' 之类），退出时原样写回。
  String? _duckPrev;

  /// 懒建 + 挂回调：offer/sdp/ice 从 room_client 进来，日志统一走 `[YQK-VOICE]`。
  VoiceEngine _voiceEngine(RoomClient rc) {
    final VoiceEngine? old = _voiceEngineOrNull;
    if (old != null) return old;
    final VoiceEngine e = VoiceEngine(
      onSend: (Map<String, dynamic> f) => rc.send(f),
      onLog: (String line) => debugPrint('[YQK-VOICE] $line'),
      onConnectTimeout: (String peer, String state) {
        if (!mounted) return;
        debugPrint('[YQK-VOICE] degrade 自动退出 peer=$peer state=$state');
        _snack('语音连接失败，已退出');
        unawaited(_leaveVoiceAsync());
      },
    );
    rc.onP2P = (Map<String, dynamic> f) {
      if (f['screen'] == true) {
        unawaited(_screenEngine(rc).onSignal(f));
      } else {
        unawaited(e.onSignal(f));
      }
    };
    _voiceEngineOrNull = e;
    return e;
  }

  ScreenEngine? _screenEngineOrNull;

  /// M10 C 组：本机当 DLNA renderer 的轮询桥（只有房主房间内才有实例）。
  DlnaRendererBridge? _dlnaBridge;

  /// M10 B 组：当前投屏目标（非空时把播放/暂停/拖动同步过去）
  DlnaSender? _castDevice;
  Duration _castLastPos = Duration.zero;
  bool _castLastPlaying = false;

  /// 当前要画在 video 区上的屏幕轨：客人侧是远端 track，房主侧是本地预览。
  MediaStreamTrack? _remoteScreen;

  /// D20 第二步：信令总入口。screen 帧永远不给语音引擎，语音帧也不给屏幕引擎。
  ///
  /// 屏幕上线的门槛比语音低（不要求在语音里），所以这个挂载必须与「进没进语音」无关。
  void _bindP2P(RoomClient rc) {
    rc.onP2P = (Map<String, dynamic> f) {
      if (f['screen'] == true) {
        unawaited(_screenEngine(rc).onSignal(f));
      } else {
        unawaited(_voiceEngineOrNull?.onSignal(f) ?? Future<void>.value());
      }
    };
  }

  /// 屏幕引擎懒建：只有真的共享/真的收到屏幕 offer 时才存在。
  ScreenEngine _screenEngine(RoomClient rc) {
    final ScreenEngine? old = _screenEngineOrNull;
    if (old != null) return old;
    final ScreenEngine e = ScreenEngine(
      onSend: (Map<String, dynamic> f) => rc.send(f),
      onLog: (String line) {
        debugPrint(line.startsWith('[YQK-') ? line : '[YQK-SCREEN] $line');
        // 房主停共享没有 close 信令，收端只会看到 Disconnected/Failed：
        // 这时把画面上那条轨摘掉，回落到本机播放。
        if (line.contains('RTCPeerConnectionStateDisconnected') ||
            line.contains('RTCPeerConnectionStateFailed')) {
          if (mounted && _remoteScreen != null) {
            debugPrint('[YQK-SCREEN] view cleared reason=disconnected');
            setState(() => _remoteScreen = null);
          }
        }
      },
      onRemoteTrack: (String peer, MediaStreamTrack t) {
        debugPrint('[YQK-SCREEN] attach view peer=$peer kind=${t.kind}');
        if (!mounted) return;
        setState(() => _remoteScreen = t);
      },
    );
    _screenEngineOrNull = e;
    return e;
  }

  /// 当前房间里该收屏幕轨的人：除自己以外的在线、非 bot 成员。
  List<String> _roomClientPeerIds(RoomClient rc) {
    final RoomSnapshot? snap = rc.snapshot.value;
    if (snap == null) return <String>[];
    final String? me = rc.memberId;
    return snap.members
        .where((RoomMember m) => m.id != me && m.online && !m.isBot)
        .map((RoomMember m) => m.id)
        .toList();
  }

  /// 两个语音监听器的闭包：dispose 时要能逐个摘掉，
  /// 否则 RoomClient 活得比页面久，每次重进播放页都会多挂一个（泄漏）。
  VoidCallback? _voiceNoticeFn;
  VoidCallback? _voicePeersFn;

  /// 服务端 voice-full / voice-error 的一次性提示：弹完就清空，避免重建时重复弹。
  void _bindVoiceNotice(RoomClient rc) {
    void fn() {
      final String t = rc.voiceNotice.value;
      if (t.isEmpty || !mounted) return;
      rc.voiceNotice.value = '';
      _snack(t);
    }

    _voiceNoticeFn = fn;
    rc.voiceNotice.addListener(fn);
  }

  /// 语音成员表变化 → 交给 engine 建/拆连接（Mesh：n 人 = n-1 条 PC）。
  void _bindVoicePeers(RoomClient rc) {
    void fn() {
      if (!mounted) return;
      final VoiceState vs = rc.voiceState.value;
      if (!vs.joined) return;
      final List<String> peers = vs.items
          .map((VoiceMember m) => m.id)
          .where((String id) => id != rc.memberId)
          .toList();
      unawaited(_voiceEngine(rc).reconcile(peers));
    }

    _voicePeersFn = fn;
    rc.voiceState.addListener(fn);
  }

  /// 成员条：语音状态是独立的 ValueNotifier，包一层让 🎤 能单独重建
  /// （整页 setState 会把播放器也带着重建，没必要）。
  Widget _voiceMemberBar({required bool embedded}) {
    final RoomClient rc = widget.roomClient!;
    return ValueListenableBuilder<VoiceState>(
      valueListenable: rc.voiceState,
      builder: (BuildContext ctx, VoiceState vs, Widget? _) => RoomMemberBar(
        snapshot: rc.snapshot,
        memberId: rc.memberId,
        embedded: embedded,
        voiceIds: vs.ids,
        onMute: (String id, bool muted) => _muteMember(id, muted),
        onKick: (String id) => _kickMember(id),
      ),
    );
  }

  /// 说话条：同上，麦克风按钮的状态跟着 voiceState 走；
  /// 服务端语音总开关（rc.voiceEnabled）为 false 时麦克风整个不渲染。
  Widget _voiceChatBar({required bool embedded}) {
    final RoomClient rc = widget.roomClient!;
    return ValueListenableBuilder<VoiceState>(
      valueListenable: rc.voiceState,
      builder: (BuildContext ctx, VoiceState vs, Widget? _) =>
          ValueListenableBuilder<bool>(
        valueListenable: rc.voiceEnabled,
        builder: (BuildContext ctx2, bool voiceOn, Widget? _) => RoomChatBar(
          snapshot: rc.snapshot,
          memberId: rc.memberId,
          embedded: embedded,
          danmakuEnabled: _dm.sendEnabled,
          onDanmakuToggle: (bool v) => _setDanmakuSend(v),
          onSend: _sendChat,
          voiceJoined: vs.joined,
          voiceFull: vs.full,
          voiceEnabled: voiceOn,
          onVoiceTap: _toggleVoice,
          onVoiceLeave: _leaveVoice,
        ),
      ),
    );
  }

  /// 弹幕层的位置与命中框（长按命中用）。
  ///
  /// 事件源是视频手势层（_gestureLayer 在 Stack 里压着弹幕层且 opaque），
  /// 它拿全局坐标换算到弹幕层本地坐标后，用这份矩形判命中。
  final GlobalKey _dmLayerKey = GlobalKey();
  List<({String id, Rect rect})> _dmRects = const <({String id, Rect rect})>[];

  /// 去重：同一 id 300ms 内只认一次（弹幕层自己的长按与手势层委派万一都命中）
  String _lastLikeId = '';
  DateTime _lastLikeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 长按命中弹幕就点赞并返回 true（此时不叠加「长按 2 倍速」）。
  bool _tryLikeAt(Offset global) {
    final RenderBox? box =
        _dmLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final Offset p = box.globalToLocal(global);
    final String? id = DanmakuPainter.hitTestRects(_dmRects, p);
    final String at = 'x=${p.dx.toStringAsFixed(1)} y=${p.dy.toStringAsFixed(1)}';
    if (id == null) {
      debugPrint('[YQK-DM] like miss $at');
      return false;
    }
    debugPrint('[YQK-DM] like hit id=$id $at');
    // E7 B 组：长按不再直接点赞，先弹两项（点赞 / 收藏这条）
    unawaited(_openDanmakuMenu(id));
    return true;
  }

  /// 按 id 找当前这屏里的那条弹幕（拿文本用）
  RoomDanmaku? _danmakuById(String id) {
    final List<RoomDanmaku> items =
        widget.roomClient?.danmakus.value ?? const <RoomDanmaku>[];
    for (final RoomDanmaku d in items) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// 长按菜单：点赞（原行为）/ 收藏这条（F11）
  Future<void> _openDanmakuMenu(String id) async {
    final RoomDanmaku? d = _danmakuById(id);
    final String text = d?.text ?? '';
    debugPrint('[YQK-DM] menu id=$id text=$text');
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.thumb_up_outlined,
                  size: 20, color: AppColors.text),
              title: Text(
                  text.isEmpty
                      ? '点赞'
                      : '点赞「${text.length > 12 ? '${text.substring(0, 12)}…' : text}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 14)),
              onTap: () => Navigator.of(ctx).pop('like'),
            ),
            ListTile(
              leading: Icon(Icons.bookmark_add_outlined,
                  size: 20, color: AppColors.text),
              title: Text('收藏这条',
                  style: TextStyle(color: AppColors.text, fontSize: 14)),
              subtitle: Text('存进「弹幕库」，以后能搜到',
                  style: TextStyle(color: AppColors.textSub, fontSize: 11)),
              onTap: () => Navigator.of(ctx).pop('fav'),
            ),
            // H2：没配翻译服务时不显示（NoopTranslator → isConfigured=false）
            if (_translator.isConfigured)
              ListTile(
                leading: Icon(Icons.translate,
                    size: 20, color: AppColors.text),
                title: Text('翻译',
                    style: TextStyle(color: AppColors.text, fontSize: 14)),
                subtitle: Text('用你配置的翻译服务译成中文',
                    style: TextStyle(color: AppColors.textSub, fontSize: 11)),
                onTap: () => Navigator.of(ctx).pop('translate'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    _restartHideTimer();
    if (pick == 'like') {
      _likeDanmaku(id);
    } else if (pick == 'fav') {
      await _favDanmaku(d);
    } else if (pick == 'translate') {
      await _translateText(text, source: 'danmaku');
    }
  }

  /// H2：译一句话并用 SnackBar 显示「原文 → 译文」。不落库、不上报。
  Future<void> _translateText(String text, {required String source}) async {
    final String q = text.trim();
    if (q.isEmpty) return;
    debugPrint('[YQK-TRANS] ask source=$source len=${q.length}');
    final String? r = await _translator.translate(q);
    debugPrint('[YQK-TRANS] done source=$source ok=${r != null}');
    if (!mounted) return;
    if (r == null) {
      _snack('翻译失败：检查设置里的翻译服务');
      return;
    }
    _snack('$q → $r');
  }

  /// F11：把这条弹幕存进弹幕库（text + 当前片子 url 去重）
  Future<void> _favDanmaku(RoomDanmaku? d) async {
    final AppDatabase? db = _db;
    if (db == null || d == null || d.text.isEmpty) {
      debugPrint('[YQK-DM] fav skip no-db-or-text');
      return;
    }
    final PlayerMedia m = _controller?.media ?? widget.media;
    final bool added = await db.danmakuDao.favPut(
      text: d.text,
      mediaUrl: m.url,
      pos: d.pos,
      room: widget.roomClient?.roomCode ?? '',
      at: d.at == 0 ? null : d.at,
    );
    debugPrint('[YQK-DM] fav id=${d.id} new=$added url=${m.url}');
    if (!mounted) return;
    _snack(added ? '已收藏到弹幕库' : '这条已经在弹幕库了');
  }

  /// F11：房间内快速打开「弹幕库」（只看本房间收的）
  Future<void> _openDanmakuLibrary() async {
    final String code = widget.roomClient?.roomCode ?? '';
    debugPrint('[YQK-DMLIB] open room=$code');
    _restartHideTimer();
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (BuildContext _) => DanmakuLibraryPage(
          initialRoom: code.isEmpty ? null : code,
          onRoomChanged: (String? r) =>
              debugPrint('[YQK-DMLIB] filter changed room=${r ?? 'all'}'),
          onJump: _jumpToDanmaku,
        ),
      ),
    );
  }

  /// F4 播放列表：把当前片子加进某个列表（没有就当场新建一个）。
  ///
  /// 列表名存在 playlists.name 上，条目按 sortIndex 排；空列表用一条
  /// mediaUrl='' 的占位行表示，所以这里只管往里 addItem。
  Future<void> _addToPlaylist() async {
    final PlayerMedia? m = _controller?.media ?? widget.media;
    if (m == null) {
      _snack('还没选片子');
      return;
    }
    _restartHideTimer();
    final List<String> names = await _db!.playlistDao.names();
    if (!mounted) return;
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) {
        final List<String> fresh = <String>[...names];
        return StatefulBuilder(
          builder: (BuildContext c, StateSetter setSheet) {
            Future<void> make() async {
              final TextEditingController tc = TextEditingController();
              final String? v = await showDialog<String>(
                context: c,
                builder: (BuildContext d) => AlertDialog(
                  title: const Text('新建列表'),
                  content: TextField(
                    controller: tc,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '列表名，如「周末片单」'),
                    onSubmitted: (String v) => Navigator.of(d).pop(v),
                  ),
                  actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.of(d).pop(''),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.of(d).pop(tc.text),
                        child: const Text('确定')),
                  ],
                ),
              );
              tc.dispose();
              final String name = (v ?? '').trim();
              if (name.isEmpty) return;
              final bool ok = await _db!.playlistDao.create(name);
              debugPrint('[YQK-PL] create name=$name ok=$ok');
              if (ok && !fresh.contains(name)) {
                setSheet(() => fresh.add(name));
              }
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('加入列表…'),
                    ),
                  ),
                  if (fresh.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 6, 18, 10),
                      child: Text('还没有列表，先建一个'),
                    ),
                  for (final String n in fresh)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(c).pop(n),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建列表'),
                    onTap: () => unawaited(make()),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null || picked.isEmpty) return;
    final bool ok = await _db!.playlistDao.addItem(
      picked,
      m.url,
      m.title.isEmpty ? m.url : m.title,
    );
    debugPrint('[YQK-PL] add name=$picked ok=$ok url=${m.url}');
    _snack(ok ? '已加入「$picked」' : '「$picked」里已经有这条了');
  }

  /// 弹幕库点一条 → 跳到当时的位置（片子对不上就提示，不硬跳）。
  void _jumpToDanmaku(String url, int posMs) {
    final PlayerMedia? m = _controller?.media;
    if (m != null && m.url == url) {
      unawaited(_controller!.seek(Duration(milliseconds: posMs)));
      debugPrint('[YQK-DMLIB] jump pos=$posMs url=$url');
      Navigator.of(context).pop();
    } else {
      _snack('先打开这条弹幕所属的片子');
      debugPrint('[YQK-DMLIB] jump miss url=$url now=${m?.url ?? '-'}');
    }
  }

  /// 长按某条弹幕点赞：本地先 +1（数字立刻变），再发 danmaku-like 帧。
  ///
  /// 乐观更新与服务端增量走 RoomClient 的 max 合并，两边都 +1 不会互相冲掉。
  void _likeDanmaku(String id) {
    final RoomClient? rc = widget.roomClient;
    if (rc == null || id.isEmpty) return;
    final DateTime now = DateTime.now();
    if (id == _lastLikeId &&
        now.difference(_lastLikeAt) < const Duration(milliseconds: 300)) {
      debugPrint('[YQK-DM] like dedupe id=$id');
      return;
    }
    _lastLikeId = id;
    _lastLikeAt = now;
    rc.bumpDanmakuLike(id);
    rc.send(<String, dynamic>{'type': 'danmaku-like', 'id': id});
    debugPrint('[YQK-DM] like send id=$id');
  }

  /// 弹幕开关键：写回设置并持久化（与弹幕设置面板共用同一套 prefs）。
  Future<void> _setDanmakuSend(bool on) async {
    if (_dm.sendEnabled == on) return;
    setState(() => _dm = _dm.copyWith(sendEnabled: on));
    await _saveDanmakuSettings();
    debugPrint('[YQK-DM] send switch=${on ? 'on' : 'off'}');
  }

  /// debug 专用：一次发三条「短 / 中 / 长」，宽度约 90 / 360 / 440px。
  ///
  /// 用途：验收「固定时间穿屏 8 秒」和「超长截断到一屏宽 + …」这两条——
  /// 三条同一 pos 出发，painter 的 [YQK-DM] trace 会打出各自的 w / v / cross，
  /// 截图里能直接看到 200 字那条的「…」。
  void _sendDebugDanmakuTrio() {
    final PlayerController? c = _controller;
    final RoomClient? rc = widget.roomClient;
    if (c == null || rc == null) return;
    final double pos =
        double.parse((c.position.inMilliseconds / 1000.0).toStringAsFixed(2));
    final Map<String, String> texts = <String, String>{
      'short': '短弹幕九十字', // 6 字 ≈ 90px
      'mid': '中弹幕${'中' * 21}', // 24 字 ≈ 360px
      'long': '长弹幕${'测' * 197}', // 200 字 → 截断到一屏宽
    };
    final int stamp = DateTime.now().microsecondsSinceEpoch;
    for (final MapEntry<String, String> e in texts.entries) {
      rc.send(<String, dynamic>{
        'type': 'danmaku',
        'text': e.value,
        'pos': pos,
        'color': 16777215,
        'mode': 'scroll',
        'size': 1.0,
        'bold': false,
      });
      rc.debugInjectDanmaku(RoomDanmaku(
        id: 'dbg_${e.key}_$stamp',
        from: rc.memberId ?? '',
        name: '我',
        text: e.value,
        pos: pos,
        at: DateTime.now().millisecondsSinceEpoch,
        color: 16777215,
        mode: 'scroll',
        size: 1.0,
      ));
    }
    debugPrint('[YQK-DM] debug trio pos=${pos.toStringAsFixed(2)} '
        'short/mid/long ×1');
    _hideTimer?.cancel();
    if (_controlsVisible) setState(() => _controlsVisible = false);
  }

  /// H3 过滤子项的小圆角开关（弹幕设置面板里用）
  Widget _dmFilterChip(String label, bool on, void Function(bool) onChanged) =>
      Padding(
        padding: const EdgeInsets.only(right: 2),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: on,
          visualDensity: VisualDensity.compact,
          onSelected: onChanged,
        ),
      );

  /// 弹幕设置面板（最小版：开关 + 三档透明度 / 速度 / 字号）
  Future<void> _openDanmakuSettings() async {
    DanmakuSettings draft = _dm;
    final DanmakuSettings? out = await showModalBottomSheet<DanmakuSettings>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheet) {
            Widget row(String label, List<Widget> chips) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 56,
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textDim)),
                      ),
                      ...chips,
                    ],
                  ),
                );
            Widget chip(String text, bool on, VoidCallback onTap) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(text, style: const TextStyle(fontSize: 12)),
                    selected: on,
                    onSelected: (_) => onTap(),
                  ),
                );
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    child: Row(
                      children: <Widget>[
                        const Text('弹幕设置',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Switch(
                          value: draft.visible,
                          onChanged: (bool v) =>
                              setSheet(() => draft = draft.copyWith(visible: v)),
                        ),
                      ],
                    ),
                  ),
                  row('透明度', <Widget>[
                    chip('0.3', draft.opacity == 0.3,
                        () => setSheet(() => draft = draft.copyWith(opacity: 0.3))),
                    chip('0.5', draft.opacity == 0.5,
                        () => setSheet(() => draft = draft.copyWith(opacity: 0.5))),
                    chip('0.85', draft.opacity == 0.85,
                        () => setSheet(() => draft = draft.copyWith(opacity: 0.85))),
                  ]),
                  row('速度', <Widget>[
                    chip('慢', draft.speed == 80,
                        () => setSheet(() => draft = draft.copyWith(speed: 80))),
                    chip('中', draft.speed == 120,
                        () => setSheet(() => draft = draft.copyWith(speed: 120))),
                    chip('快', draft.speed == 180,
                        () => setSheet(() => draft = draft.copyWith(speed: 180))),
                  ]),
                  row('字号', <Widget>[
                    chip('小', draft.fontSize == 13,
                        () => setSheet(() => draft = draft.copyWith(fontSize: 13))),
                    chip('中', draft.fontSize == 15,
                        () => setSheet(() => draft = draft.copyWith(fontSize: 15))),
                    chip('大', draft.fontSize == 18,
                        () => setSheet(() => draft = draft.copyWith(fontSize: 18))),
                  ]),
                  // H3：弹幕过滤（总开关 + 五条规则）。只挡别人发的，
                  // 自己发的永远显示，所以设置里写清这一点。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 56,
                          child: Text('过滤',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textDim)),
                        ),
                        Expanded(
                          child: Text('挡掉刷屏/重复/剧透（自己发的不过滤）',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textDim)),
                        ),
                        Switch(
                          value: draft.filterEnabled,
                          onChanged: (bool v) => setSheet(
                              () => draft = draft.copyWith(filterEnabled: v)),
                        ),
                      ],
                    ),
                  ),
                  if (draft.filterEnabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          _dmFilterChip(
                            '太短',
                            draft.filterOptions.tooShort,
                            (bool v) => setSheet(() => draft = draft.copyWith(
                                filterOptions:
                                    draft.filterOptions.copyWith(tooShort: v))),
                          ),
                          _dmFilterChip(
                            '太长',
                            draft.filterOptions.tooLong,
                            (bool v) => setSheet(() => draft = draft.copyWith(
                                filterOptions:
                                    draft.filterOptions.copyWith(tooLong: v))),
                          ),
                          _dmFilterChip(
                            '重复',
                            draft.filterOptions.repeat,
                            (bool v) => setSheet(() => draft = draft.copyWith(
                                filterOptions:
                                    draft.filterOptions.copyWith(repeat: v))),
                          ),
                          _dmFilterChip(
                            '刷屏',
                            draft.filterOptions.spam,
                            (bool v) => setSheet(() => draft = draft.copyWith(
                                filterOptions:
                                    draft.filterOptions.copyWith(spam: v))),
                          ),
                          _dmFilterChip(
                            '剧透',
                            draft.filterOptions.spoiler,
                            (bool v) => setSheet(() => draft = draft.copyWith(
                                filterOptions:
                                    draft.filterOptions.copyWith(spoiler: v))),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(draft),
                        child: const Text('完成'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (out == null || !mounted) return;
    setState(() => _dm = out);
    await _saveDanmakuSettings();
  }

  bool _fatalHandled = false;

  /// 4 号必修的第二段：原地重试也失败 → 作废这条直链的缓存，重新解析一次再开
  Future<void> _handleFatal(PlayerMedia media, String message) async {
    if (_fatalHandled) return;
    _fatalHandled = true;
    debugPrint('[YQK-RETRY] 判定直链失效，作废缓存并重新解析：$message');
    final Resolver resolver = ProviderScope.containerOf(context).read(resolverProvider);
    // 缓存 key 可能挂在「页面地址」（B 站/番剧）上，也可能挂在「直链」上：两处都作废
    resolver.invalidate(media.url);
    if (media.id.startsWith('http') && media.id != media.url) {
      resolver.invalidate(media.id);
    }
    final String refreshTarget =
        media.id.startsWith('http') && media.id != media.url ? media.id : media.url;
    debugPrint('[YQK-RETRY] backend_refresh 目标：$refreshTarget');
    if (!mounted) return;
    setState(() => _openError = '直链失效了，正在重新解析…');
    try {
      final ResolvedUrl fresh = await resolver.resolve(refreshTarget);
      await _controller?.open(media.copyWithUrl(fresh.url), autoplay: true);
      if (mounted) setState(() => _openError = null);
    } on Object catch (e) {
      debugPrint('[YQK-RETRY] 重新解析后仍不开：$e');
      if (mounted) setState(() => _openError = FailureText.lineOf(e));
    }
  }

  Future<void> _boot() async {    // 先记下系统原值，再让用户动它
    await _captureSystemValues();

    final AppDatabase db = widget.database ?? AppDatabase();
    if (widget.database == null) _ownsDb = true;
    _db = db;
    debugPrint('[YQK-SUB] db schema=${db.schemaVersion}');

    final Prefs prefs = await Prefs.open();
    // 内核由控制器按 pref（auto/mpv/fvp）自己造，fvp 起不来会自动退回 mpv
    final PlayerController controller =
        widget.controller ?? PlayerController(history: db.historyDao, prefs: prefs);
    if (!mounted) return;
    setState(() => _controller = controller);
    controller.addListener(_onControllerChanged);
    _bindEndedListener(controller);
    // 跟随播放：只在这一处监听权威位置（房间浮层与手势都不碰播放器状态）
    widget.roomClient?.authTick.addListener(_onAuthoritative);
    widget.roomClient?.claimGranted.addListener(_onClaimGranted);
    widget.roomClient?.rejectedClaim.addListener(_onClaimResult);
    widget.roomClient?.hostNotice.addListener(_onHostNotice);
    widget.roomClient?.mediaFrame.addListener(_onMediaFrame);
    // I-57：按角色下发一次本地连播开关（客人在 open 之前就要设好，
    // 否则第一集结尾会先本地 advance 一次）。房主身份变化时由快照回调重算。
    widget.roomClient?.snapshot.addListener(_onSnapshotForAutoNext);
    _applyAutoNextForRole(controller);
    _stateSub = widget.roomClient?.states.listen(_onClientState);
    // D22：客人这边靠这个流自动弹「一起看网页」，房主自己也监听但只会被 open 触发一次
    _webSub = widget.roomClient?.webEvents.listen(_onWebEvent);
    _noticeSub = controller.notices.listen(_showNotice);
    // 4 号必修：原地重试也失败 → 判定直链失效，作废缓存并重开一次（只一次）
    controller.onFatal = (PlayerMedia media, String message) {
      unawaited(_handleFatal(media, message));
    };

    try {
      // 15 §A12：没显式指定起点时，按上次进度续播（(5, duration-10) 区间才续）
      final KernelKind? wanted = widget.kernelKind;
      if (wanted != null) await controller.setKernelKind(wanted);
      final Duration start =
          widget.startAt ?? await controller.resumeStart(widget.media);
      // 04 §12.6.1 / §12.6.2：Android 上这套 libmpv 挂用户着色器会静默黑屏
      // （实测连一段反色 shader 都黑），画质档位已整体撤掉，界面不再有档位入口；
      // Anime4k.setAnimeLevel 在 Android 分支直接 return，这里只是保留调用点。
      if (widget.anime4k != Anime4kLevel.off) {
        await Anime4k.setAnimeLevel(controller.kernel, widget.anime4k);
      }
      if (widget.playlist.isNotEmpty) {
        // 片单：上一集/下一集/自动连播都靠它（M3 接线，M4 真机验）
        controller.setPlaylist(widget.playlist, currentId: widget.media.id);
      }
      if (widget.roomClient != null && widget.media.url.isEmpty) {
        // 客人进房：片源不在本地参数里，等房主的第一个快照。
        // 顺序必须是 open(autoplay:false) → 等 duration → seek → play（06 坑表第 28 条）。
        await _openFromRoomSnapshot(controller);
      } else {
        await controller.open(widget.media,
            start: start, autoplay: widget.autoplay);
      }
      // I-6 B 方案：fvp 的内嵌字幕文本回调在真机是 0 次，所以本地 MKV 自己抽出来，
      // 走已经打通的外挂字幕路径（Flutter 自绘）。抽不出来就静默跳过。
      await _tryExtractEmbeddedSubtitle();
      // H4：读一次章节（没有就空表）＋读手动标记；两个跳过开关的默认值也从这里来
      unawaited(_loadChapters(controller));
    } on Object catch (e) {
      debugPrint('[YQK-OPEN] 打开失败：$e');
      // 打不开就给人话提示，别让用户对着黑屏等
      // 15 §B20：五种失败各一句人话，原始异常只进日志
      if (mounted) setState(() => _openError = FailureText.lineOf(e));
    }
    if (kDebugMode && widget.audioTrack != null) {
      await controller.setAudioTrack(widget.audioTrack! - 1);
    }
    if (kDebugMode) {
      await _applyDebugOverrides(controller);
    }
    await _applyHold();
    if (kDebugMode && widget.openAdvanced && mounted) {
      unawaited(context.push(Routes.playerAdvanced, extra: controller));
    }
    final Duration? exitAfter = widget.autoExitAfter;
    if (kDebugMode && exitAfter != null) {
      // 验收用：到点自己退回上一页，走正常 dispose，好验证亮度/音量还原
      debugPrint('[YQK-EXIT] 将在 ${exitAfter.inSeconds}s 后退出播放页');
      Timer(exitAfter, () {
        debugPrint('[YQK-EXIT] 现在退出');
        if (!mounted) return;
        final NavigatorState nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.maybePop();
        } else {
          // 深链直接落到 /play 时栈里没有上一页，回首页同样会走 dispose
          context.go(Routes.home);
        }
      });
    }
    _startProgressPublish();
    _restartHideTimer();
  }

  /// 内核降级/连播这类一次性提示：只出一条轻提示，不弹窗打断
  void _showNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 从本地 MKV 里抽内嵌文本字幕；成功就挂上并喂给自绘层。
  /// 图形字幕（PGS/VOBSUB）只打一行日志，不打扰用户（06 §3.4：失败要给人话，
  /// 但"这条轨本来就没有文本"不算失败）。
  Future<void> _tryExtractEmbeddedSubtitle() async {
    if (_subData != null) return; // 用户自己挂了字幕就不覆盖
    final String? path = _localPathOf(widget.media.url);
    if (path == null) return;
    final ExtractedSubtitle? ex =
        await MkvSubtitleExtractor.extractFromFile(path);
    if (ex == null) return;
    if (!mounted) return;
    if (ex.imageBased) {
      debugPrint('[YQK-MKVSUB] 这条是图形字幕（${ex.codecId}），跳过');
      return;
    }
    if (!ex.hasText) {
      debugPrint('[YQK-MKVSUB] 有文本轨但没抽到字幕块（codec=${ex.codecId}）');
      return;
    }
    debugPrint('[YQK-MKVSUB] 抽出内嵌字幕 cues=${ex.cueCount} '
        'codec=${ex.codecId} -> ${ex.path}');
    try {
      await _controller?.kernel.setSubtitle(ex.path, title: '内嵌字幕');
    } on Object catch (e) {
      debugPrint('[YQK-MKVSUB] 交给内核失败（自绘照常）：$e');
    }
    await _loadSubtitleData(ex.path);
  }

  /// 只接受本地文件：http(s) 不下载（那属于缓存/下载模块的事）
  String? _localPathOf(String url) {
    if (url.startsWith('file://')) {
      try {
        return Uri.parse(url).toFilePath();
      } on Object {
        return null;
      }
    }
    if (url.contains('://')) return null;
    return url;
  }

  /// 把字幕文件解析成纯文本时间轴，交给 Flutter 层自绘（见 subtitle_overlay.dart）
  Future<void> _loadSubtitleData(String source) async {
    try {
      // 走一遍 SubtitleLoader：GBK 会在这里转成 UTF-8，自绘拿到的才是能显示的文本
      final String utf8Path = await SubtitleLoader().prepare(source);
      final SubtitleData data = await SubtitleData.load(utf8Path);
      if (!mounted) return;
      setState(() => _subData = data);
      debugPrint('[YQK-SUB] 自绘字幕已就绪 cues=${data.cues.length}');
    } on Object {
      // 解析失败不影响 mpv 那边照挂，只是屏幕上可能没字
      debugPrint('[YQK-SUB] 自绘字幕解析失败');
    }
  }
  /// 验收钩子（只在 debug 生效）：把 app_router 从深链读到的参数逐条落到播放器上。
  /// 顺序有意义：先挂音轨/字幕（要重新读 track-list），再设倍速与比例。
  Future<void> _applyDebugOverrides(PlayerController c) async {
    final String? sub = widget.subtitlePath;
    if (sub != null && sub.isNotEmpty) {
      await c.setSubtitle(sub, label: sub.split(Platform.pathSeparator).last);
      await _loadSubtitleData(sub);
    }
    // 15 §A5 四步排查：subprops 逐条写（sub-visibility / sub-ass / sub-pos …）
    if (widget.subProps.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await c.applyRawProperties(widget.subProps);
    }

    final String? audio = widget.audioFile;
    if (audio != null && audio.isNotEmpty) {
      try {
        await c.addExternalAudio(audio);
      } on Object catch (e) {
        debugPrint('[YQK-AUDIOFILE] 挂外挂音轨失败：$e');
      }
    }

    // 外挂音轨挂上时 addExternalAudio 已经自动切过去了；这里只在没挂外挂音轨时
    // 用深链传进来的 aid 做覆盖（调试用）
    final int? aid = widget.audioTrack;
    if (aid != null && (widget.audioFile ?? '').isEmpty) {
      await c.setAudioTrack(aid - 1);
    }

    final double? rate = widget.rateOverride;
    if (rate != null) await c.setRate(rate);

    final int? aspect = widget.aspectIndex;
    if (aspect != null && aspect >= 0 && aspect < AspectMode.values.length) {
      await c.setAspect(AspectMode.values[aspect]);
    }

    final double? bright = widget.brightnessOverride;
    if (bright != null) {
      await _applyBrightness(bright.clamp(0.0, 1.0));
      debugPrint('[YQK-BRIGHT] set=${bright.clamp(0.0, 1.0)} '
          'appLevel=$_brightnessIsApplicationLevel');
    }

    final double? vol = widget.volumeOverride;
    if (vol != null) {
      await _applyVolume(vol.clamp(0.0, 1.0));
      final double back = await VolumeController.instance.getVolume();
      debugPrint('[YQK-VOLUME] set=${vol.clamp(0.0, 1.0)} readback=$back');
    }

    // 请求头是否真的进了 mpv（验收 M2-1 要这一行）
    final String? hf = await c.kernel.readProperty('http-header-fields');
    debugPrint('[YQK-HEADERS] http-header-fields=$hf');
  }

  /// 验收钩子（只在 debug 生效）：先让 mpv 真正出帧，再暂停并精确 seek，
  /// 这样两次启动能停在完全相同的一帧上做像素比对。
  Future<void> _applyHold() async {
    final Duration? hold = widget.holdAt;
    final PlayerController? c = _controller;
    if (!kDebugMode || hold == null || c == null) return;
    // fvp 要 6 秒左右才 ready：先等真正出帧（position > 0），最多等 defer 窗口，
    // 否则 1.5 秒就 seek 会被播放器丢掉，截图停在 00:00。
    final DateTime deadline =
        DateTime.now().add(PlayerController.deferReadyTimeout);
    while (c.position <= Duration.zero && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await c.pause();
    await c.seek(hold);
    debugPrint('[YQK-HOLD] paused at ${hold.inMilliseconds}ms');
  }

  Future<void> _captureSystemValues() async {
    // 只用「应用级亮度」：改系统亮度要 WRITE_SETTINGS，会弹「修改系统设置」
    // 系统对话框，播放页一进来就被挡住，体验不能接受。
    try {
      _originalBrightness = await ScreenBrightness().application;
      _brightnessIsApplicationLevel = true;
      debugPrint('[YQK-BRIGHT] capture original='
          '${_originalBrightness!.toStringAsFixed(2)}');
    } on Object catch (e) {
      _originalBrightness = null;
      debugPrint('[YQK-BRIGHT] capture failed: $e');
    }
    try {
      _originalVolume = await VolumeController.instance.getVolume();
    } on Object {
      _originalVolume = null;
    }
  }

  void _onControllerChanged() {
    // 内核可能被换掉（fvp 起不来退回 mpv / 手动切内核），换了就重新挂事件流
    final PlayerController? c = _controller;
    if (c != null) _bindEndedListener(c);
    final PlayerMedia? now = c?.media;
    if (now != null) unawaited(_scanSubtitlesOnce(now));
    // D12：拖回片中要复位，否则只切一次集
    if (_endedFired && c != null) {
      final Duration dur = c.duration;
      if (dur > Duration.zero &&
          c.position < dur - const Duration(seconds: 1)) {
        _endedFired = false;
        debugPrint('[YQK-CONTROL] ended 复位（pos=${c.position.inMilliseconds}ms）');
      }
    }
    if (mounted) setState(() {});
    _syncCast(c);
    // H4：每次位置变化都判一次该不该跳片头
    _applySkip(c);
  }

  /// H4：读章节 + 手动标记 + 两个开关（进片一次）。
  Future<void> _loadChapters(PlayerController c) async {
    // 章节要等 demux 出 duration 之后才有；这里轮询几次，最多 ~3.2 秒
    List<MediaChapter> list = const <MediaChapter>[];
    int tries = 0;
    for (int i = 0; i < 8; i++) {
      tries = i + 1;
      try {
        final List<MediaChapter> got = await c.kernel.chapters();
        if (got.isNotEmpty) {
          list = got;
          break;
        }
      } on Object catch (e) {
        debugPrint('[YQK-CHAP] chapters 失败：$e');
        break;
      }
      // 已经有 duration 还没章节，大概率就是这片没章节，别一直等
      if (c.duration > Duration.zero && i >= 3) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
    }
    ChapterMark? mark;
    final AppDatabase? db = _db;
    // 换片后 controller 里的才是「当前这部」，widget.media 只是进页那一条
    final String mid = c.media?.id ?? widget.media.id;
    if (db != null) {
      try {
        mark = await db.chapterMarkDao.get(mid);
      } on Object catch (e) {
        debugPrint('[YQK-CHAP] mark 读库失败：$e');
      }
    }
    bool si = false;
    bool so = false;
    try {
      final Prefs p = await Prefs.open();
      si = p.getBool(PrefKeys.chapSkipIntro) ?? false;
      so = p.getBool(PrefKeys.chapSkipOutro) ?? false;
    } on Object catch (_) {}
    _chapSkip.reset();
    if (!mounted) return;
    setState(() {
      _chapters = list;
      _chapMark = mark;
      _skipIntro = si;
      _skipOutro = so;
    });
    if (list.isEmpty) {
      debugPrint('[YQK-CHAP] count=0 tries=$tries');
    } else {
      debugPrint('[YQK-CHAP] count=${list.length} first=${list.first} tries=$tries');
    }
    if (mark != null) {
      debugPrint('[YQK-CHAP] mark intro=${mark.introEnd} outro=${mark.outroStart}');
    }
    debugPrint('[YQK-CHAP] switch intro=$si outro=$so');
  }

  /// H4：位置回调里判定并执行跳片头（每片只跳一次，见 ChapterSkip）。
  void _applySkip(PlayerController? c) {
    if (c == null || _endedFired || !c.playing) return;
    final double dur = c.duration.inMilliseconds / 1000.0;
    final double pos = c.position.inMilliseconds / 1000.0;
    if (dur <= 0 || pos <= 0) return;
    // 手动标记优先；没标过就用片源自带的章节（第一段结束 = 片头，最后一段开始 = 片尾）
    double introEnd = _chapMark?.introEnd ?? -1;
    if (introEnd <= 0 && _chapters.isNotEmpty && _chapters.first.hasEnd) {
      introEnd = _chapters.first.end;
    }
    double outroStart = _chapMark?.outroStart ?? -1;
    if (outroStart <= 0 && _chapters.length > 1) {
      outroStart = _chapters.last.start;
    }
    final SkipAction a = _chapSkip.decide(
      pos: pos,
      duration: dur,
      introEnd: introEnd,
      outroStart: outroStart,
      skipIntro: _skipIntro,
      skipOutro: _skipOutro,
    );
    if (_chapSkip.outroHit) {
      debugPrint('[YQK-CHAP] outro hit pos=${pos.toStringAsFixed(1)}');
    }
    if (a != SkipAction.toIntroEnd) return;
    final double target = introEnd;
    if (target <= 0) return;
    debugPrint('[YQK-CHAP] skip intro pos=${pos.toStringAsFixed(1)} '
        '-> ${target.toStringAsFixed(1)}');
    unawaited(c.seek(Duration(milliseconds: (target * 1000).round())));
  }

  Future<void> _setSkipIntro(bool v) async {
    setState(() => _skipIntro = v);
    try {
      final Prefs p = await Prefs.open();
      await p.setBool(PrefKeys.chapSkipIntro, v);
    } on Object catch (e) {
      debugPrint('[YQK-CHAP] 存开关失败：$e');
    }
    debugPrint('[YQK-CHAP] switch intro=$v');
  }

  Future<void> _setSkipOutro(bool v) async {
    setState(() => _skipOutro = v);
    try {
      final Prefs p = await Prefs.open();
      await p.setBool(PrefKeys.chapSkipOutro, v);
    } on Object catch (e) {
      debugPrint('[YQK-CHAP] 存开关失败：$e');
    }
    debugPrint('[YQK-CHAP] switch outro=$v');
  }

  /// H4：把当前位置标成片头结束 / 片尾开始（只写库，不动媒体文件）。
  Future<void> _markChapter({required bool intro}) async {
    final AppDatabase? db = _db;
    final PlayerController? c = _controller;
    if (db == null || c == null) return;
    final double at = c.position.inMilliseconds / 1000.0;
    final String mid = c.media?.id ?? widget.media.id;
    if (at <= 0) {
      _snack('先播一会儿再标');
      return;
    }
    try {
      if (intro) {
        await db.chapterMarkDao.put(mid, introEnd: at);
      } else {
        await db.chapterMarkDao.put(mid, outroStart: at);
      }
      final ChapterMark? m = await db.chapterMarkDao.get(mid);
      if (!mounted) return;
      setState(() => _chapMark = m);
      _chapSkip.reset();
      debugPrint('[YQK-CHAP] mark ${intro ? "intro" : "outro"}=$at id=$mid');
      _snack(intro
          ? '片头结束已设为 ${MediaChapter.short(at)}，下次自动跳过（需在设置里开启）'
          : '片尾开始已设为 ${MediaChapter.short(at)}，到点提示（需在设置里开启）');
    } on Object catch (e) {
      debugPrint('[YQK-CHAP] 标记失败：$e');
      _snack('没存上：$e');
    }
  }

  /// H4：清掉本片的手动标记
  Future<void> _clearChapterMark() async {
    final AppDatabase? db = _db;
    if (db == null) return;
    final String mid =
        _controller?.media?.id ?? widget.media.id;
    try {
      await db.chapterMarkDao.clear(mid);
      if (!mounted) return;
      setState(() => _chapMark = null);
      _chapSkip.reset();
      debugPrint('[YQK-CHAP] mark cleared id=$mid');
      _snack('本片的片头/片尾标记已清除');
    } on Object catch (e) {
      debugPrint('[YQK-CHAP] 清除失败：$e');
    }
  }

  /// H4：章节与片头片尾面板（上：章节列表；下：两个标记按钮 + 当前值 + 清除）
  Future<void> _showChapterSheet() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    final double pos = c.position.inMilliseconds / 1000.0;
    final double dur = c.duration.inMilliseconds / 1000.0;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface3,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.72),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              children: <Widget>[
                _sheetLabel('章节'),
                if (_chapters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                        AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                    child: Text('这部片子没有章节信息',
                        style:
                            TextStyle(color: AppColors.videoDim, fontSize: 13)),
                  )
                else
                  for (int i = 0; i < _chapters.length; i++)
                    ListTile(
                      dense: true,
                      leading: Text('${i + 1}',
                          style: const TextStyle(
                              color: AppColors.videoDim, fontSize: 13)),
                      title: Text(
                        _chapters[i].title.isEmpty
                            ? '第 ${i + 1} 段'
                            : _chapters[i].title,
                        style: const TextStyle(
                            color: AppColors.videoText, fontSize: 14),
                      ),
                      subtitle: Text(
                        '${MediaChapter.short(_chapters[i].start)}'
                        ' - ${_chapters[i].hasEnd ? MediaChapter.short(_chapters[i].end) : "片尾"}',
                        style: const TextStyle(
                            color: AppColors.videoDim, fontSize: 12),
                      ),
                      onTap: () {
                        unawaited(c.seek(Duration(
                            milliseconds:
                                (_chapters[i].start * 1000).round())));
                        debugPrint(
                            '[YQK-CHAP] seek chapter $i -> ${_chapters[i].start}');
                        Navigator.of(ctx).pop();
                      },
                    ),
                const Divider(height: 1),
                _sheetLabel('手动标记（只存库，不改片源）'),
                ListTile(
                  dense: true,
                  title: const Text('标记片头结束',
                      style:
                          TextStyle(color: AppColors.videoText, fontSize: 14)),
                  subtitle: Text(
                    (_chapMark?.introEnd ?? -1) > 0
                        ? '当前 ${MediaChapter.short(_chapMark!.introEnd)}'
                        : '未设',
                    style: const TextStyle(
                        color: AppColors.videoDim, fontSize: 12),
                  ),
                  trailing: Text('在 ${MediaChapter.short(pos)} 标',
                      style: TextStyle(
                          color: AppColors.primaryEnd, fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(_markChapter(intro: true));
                  },
                ),
                ListTile(
                  dense: true,
                  title: const Text('标记片尾开始',
                      style:
                          TextStyle(color: AppColors.videoText, fontSize: 14)),
                  subtitle: Text(
                    (_chapMark?.outroStart ?? -1) > 0
                        ? '当前 ${MediaChapter.short(_chapMark!.outroStart)}'
                        : '未设',
                    style: const TextStyle(
                        color: AppColors.videoDim, fontSize: 12),
                  ),
                  trailing: Text('在 ${MediaChapter.short(pos)} 标',
                      style: TextStyle(
                          color: AppColors.primaryEnd, fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(_markChapter(intro: false));
                  },
                ),
                ListTile(
                  dense: true,
                  title: const Text('清除本片标记',
                      style:
                          TextStyle(color: AppColors.videoText, fontSize: 14)),
                  subtitle: Text('总时长 ${MediaChapter.short(dur)}',
                      style: const TextStyle(
                          color: AppColors.videoDim, fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(_clearChapterMark());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    debugPrint('[YQK-CHAP] sheet open chapters=${_chapters.length}');
  }

  /// M10 B 组：投屏期间把本机的暂停/播放/拖动同步给电视（M10 判据「能播能拖」）。
  ///
  /// 只在 _castDevice 非空时工作；SOAP 都是异步的，失败只打日志不影响本地播放。
  void _syncCast(PlayerController? c) {
    final DlnaSender? d = _castDevice;
    if (d == null || c == null) return;
    if (c.playing != _castLastPlaying) {
      _castLastPlaying = c.playing;
      final bool nowPlaying = c.playing;
      final Future<void> f = nowPlaying ? d.resume() : d.pause();
      unawaited(f.then((_) {
        debugPrint('[YQK-DLNA] soap ${nowPlaying ? 'Play' : 'Pause'} ok');
      }).catchError((Object e) {
        debugPrint('[YQK-DLNA] soap ${nowPlaying ? 'Play' : 'Pause'} fail $e');
      }));
    }
    final int deltaMs = (c.position - _castLastPos).inMilliseconds;
    _castLastPos = c.position;
    if (deltaMs.abs() > 4000) {
      final Duration at = c.position;
      unawaited(d.seek(at).then((_) {
        debugPrint('[YQK-DLNA] soap Seek ok at=${at.inSeconds}s');
      }).catchError((Object e) {
        debugPrint('[YQK-DLNA] soap Seek fail $e');
      }));
    }
  }

  /// D12：把内核的 completed（mpv 的 eof / fvp 的播放完成）挂到同一个回调上。
  /// 内核每换一次对象就重挂一次，避免旧流的订阅残留在已废弃的内核上。
  void _bindEndedListener(PlayerController c) {
    final Object k = c.kernel;
    if (identical(k, _endedKernelRef)) return;
    _endedKernelRef = k;
    unawaited(_endedSub?.cancel());
    _endedSub = c.kernel.events.listen(_onPlaybackEvent);
  }

  /// D12：播完一集。房主走已有的下一集路径（:2897 那条），客人什么都不做 —— 等 next 帧。
  void _onPlaybackEvent(PlaybackEvent e) {
    if (e.kind != PlaybackEventKind.completed) return;
    final PlayerController? c = _controller;
    if (c == null || _endedFired) return;
    _endedFired = true;
    // 控制器自己的 autoNext 可能已经先跑过一集（日志里「下一集：0 -> 1」印在 ended 之前），
    // 所以用「片单下标有没有前进」判断这次是真切集，还是最后一集真的播完了。
    final int idx = c.playlistIndex;
    final bool advanced = idx > _lastPlIndex;
    _lastPlIndex = idx;
    final bool hasRoom = widget.roomClient != null;
    if (!hasRoom || !_isRoomHost(c)) {
      debugPrint('[YQK-CONTROL] ended → 非房主，等 next 帧');
      return;
    }
    if (advanced) {
      // 控制器已经切到下一集了，这里只补播放、不再调 next()（再调会跳集）
      debugPrint('[YQK-CONTROL] ended → next ep=${idx + 1} auto=true'
          '（控制器已自动连播）');
      unawaited(_resumeIfStopped(c));
      _publishNow('episode');
      return;
    }
    if (!c.hasNext) {
      debugPrint('[YQK-CONTROL] ended → next 被跳过（没有下一集）');
      return;
    }
    final int ep = (c.media?.episodeIndex ?? 0) + 2;
    debugPrint('[YQK-CONTROL] ended → next ep=$ep auto=true');
    unawaited(c.next().then((_) => _publishNow('episode')));
    unawaited(_resumeIfStopped(c));
  }

  /// D12：自动连播之后补一次 play()。
  ///
  /// 同内核二次 open() 后 FVP 会停在 PlaybackState.stopped（`_switchMedia` 里补过同样的
  /// 一次，但 ended→next 走的是 controller 自己的 `_openAt`，绕开了那段），表现就是
  /// 切到第 2 集时画面全黑、但进度条在走。等 400ms 让 prepare/loaded 落定再判断。
  Future<void> _resumeIfStopped(PlayerController c) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || !identical(c, _controller)) return;
    if (c.playing) return;
    try {
      await c.play();
      debugPrint('[YQK-CONTROL] 自动连播后补 play '
          'idx=${c.playlistIndex}/${c.playlistLength}');
    } on Object catch (err) {
      debugPrint('[YQK-CONTROL] 自动连播后补 play 失败：$err');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台/锁屏前把进度落盘（15 §A12）
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_controller?.flushProgress() ?? Future<void>.value());
    }
    // G9：真进后台且还在播 → 挂一条带 prev/play-pause/next 的通知
    if (state == AppLifecycleState.paused) {
      final PlayerController? c = _controller;
      final PlayerMedia? mm = c?.media;
      if (c != null && mm != null && c.playing) {
        unawaited(AppNotifier.instance.showPlayback(mm.title, true));
        debugPrint('[YQK-NOTIFY] playback shown title=${mm.title}');
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(AppNotifier.instance.cancel(AppNotifier.idPlayback));
      debugPrint('[YQK-NOTIFY] playback cleared on resume');
    }
  }

  /// 通知栏三个按钮：prev / toggle / next
  void _onRemoteAction(String action) {
    final PlayerController? c = _controller;
    debugPrint('[YQK-NOTIFY] remote action=$action hasController=${c != null}');
    if (c == null) return;
    switch (action) {
      case 'toggle':
        final bool before = c.playing;
        unawaited(c.togglePlay());
        debugPrint('[YQK-NOTIFY] remote toggle playing $before -> ${!before}');
      case 'prev':
        debugPrint('[YQK-NOTIFY] remote prev hasPrev=${c.hasPrev}');
        if (c.hasPrev) unawaited(c.previous());
      case 'next':
        debugPrint('[YQK-NOTIFY] remote next hasNext=${c.hasNext}');
        if (c.hasNext) unawaited(c.next());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // G9：离页先摘掉通知栏按钮的回调，避免打到已 dispose 的页面
    if (identical(PlayerRemote.onAction, _onRemoteAction)) {
      PlayerRemote.onAction = null;
    }
    unawaited(AppNotifier.instance.cancel(AppNotifier.idPlayback));
    // M10 C 组：退房/离页必须关掉接收端（不然 SSDP 还在应答，房主播放器会被外部遥控）
    unawaited(_dlnaBridge?.stop() ?? Future<void>.value());
    _dlnaBridge = null;
    _hideTimer?.cancel();
    unawaited(_noticeSub?.cancel());
    _noticeSub = null;
    unawaited(_stateSub?.cancel());
    _stateSub = null;
    unawaited(_webSub?.cancel());
    _webSub = null;
    unawaited(_endedSub?.cancel());
    _endedSub = null;
    _endedKernelRef = null;
    _controller?.removeListener(_onControllerChanged);
    widget.roomClient?.authTick.removeListener(_onAuthoritative);
    widget.roomClient?.claimGranted.removeListener(_onClaimGranted);
    widget.roomClient?.rejectedClaim.removeListener(_onClaimResult);
    widget.roomClient?.hostNotice.removeListener(_onHostNotice);
    widget.roomClient?.mediaFrame.removeListener(_onMediaFrame);
    widget.roomClient?.snapshot.removeListener(_onSnapshotForAutoNext);
    // I-57：离页恢复连播偏好（客人进房时被降级成 false，这里按原值还原；
    // 没降级过（一直是房主）就不写，免得把用户手关的连播又打开）
    final bool? autoNextBack = _autoNextBeforeDemote;
    _autoNextBeforeDemote = null;
    _autoNextRoleApplied = null;
    if (autoNextBack != null) {
      // 这里 controller 可能已经 dispose，用不通知的写入，避免
      // 「A PlayerController was used after being disposed」
      unawaited(_controller?.persistAutoNextQuiet(autoNextBack) ??
          Future<void>.value());
    }
    debugPrint('[YQK-AUTONEXT] leave restore autoNext=${autoNextBack ?? '未降级'}');
    final RoomClient? rcD = widget.roomClient;
    if (rcD != null) {
      if (_voiceNoticeFn != null) rcD.voiceNotice.removeListener(_voiceNoticeFn!);
      if (_voicePeersFn != null) rcD.voiceState.removeListener(_voicePeersFn!);
    }
    _voiceNoticeFn = null;
    _voicePeersFn = null;
    _awaitingTimer?.cancel();
    _seekSuppressTimer?.cancel();
    _speedRestore?.cancel();
    _speedRestore = null;
    _progressTimer?.cancel();
    // 离页必须拆掉所有 PC 与本地音轨，否则麦克风指示灯不会灭
    unawaited(_unduckVoice());
    unawaited(_voiceEngineOrNull?.stop() ?? Future<void>.value());
    _voiceEngineOrNull = null;
    // D20：离页停掉屏幕采集，否则投屏图标不会消失
    final ScreenEngine? seD = _screenEngineOrNull;
    _screenEngineOrNull = null;
    if (seD != null) {
      unawaited(seD.stop());
    }
    final ScreenShare? screenD = _screen;
    _screen = null;
    if (screenD != null) {
      unawaited(screenD.stop());
    }
    if (rcD != null) rcD.onP2P = null;
    // 退出播放页还原亮度/音量（硬要求）
    unawaited(_restoreSystemValues());
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _controller?.dispose();
    if (_ownsDb) unawaited(_db?.close());
    super.dispose();
  }

  Future<void> _restoreSystemValues() async {
    final double? b = _originalBrightness;
    if (b != null) {
      try {
        if (_brightnessIsApplicationLevel) {
          // 应用级亮度是页面期间临时覆盖，退出时直接撤掉覆盖最干净
          await ScreenBrightness().resetApplicationScreenBrightness();
          // 13：退出必须能证明还原了——回读窗口亮度（reset 后是系统亮度）
          final double after = await ScreenBrightness().application;
          debugPrint('[YQK-BRIGHT] restore set=${b.toStringAsFixed(2)} '
              'readback=${after.toStringAsFixed(2)} '
              'appLevel=$_brightnessIsApplicationLevel');
        }
      } on Object catch (e) {
        debugPrint('[YQK-BRIGHT] restore failed: $e');
      }
    }
    final double? v = _originalVolume;
    if (v != null) {
      try {
        await VolumeController.instance.setVolume(v);
      } on Object {
        // 同上
      }
    }
  }

  // ── 控件显隐 ────────────────────────────────────────────
  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _restartHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ── 手势 ────────────────────────────────────────────────
  void _onDoubleTapDown(TapDownDetails d) {
    final double w = context.size?.width ?? 1;
    final double x = d.localPosition.dx;
    final PlayerController? c = _controller;
    if (c == null) return;

    if (x < w / 3) {
      final Duration target =
          _clampToMedia(c.position - const Duration(seconds: 10), c.duration);
      if (!_canControlLocally(c)) {
        _requestClaim('seek', position: target);
      } else {
        unawaited(c.seek(target));
        _publishNow('seek', at: target);
      }
      _showSeekPreview(target);
    } else if (x > w * 2 / 3) {
      final Duration target =
          _clampToMedia(c.position + const Duration(seconds: 10), c.duration);
      if (!_canControlLocally(c)) {
        _requestClaim('seek', position: target);
      } else {
        unawaited(c.seek(target));
        _publishNow('seek', at: target);
      }
      _showSeekPreview(target);
    } else {
      if (!_canControlLocally(c)) {
        _requestClaim(c.playing ? 'pause' : 'play');
        _restartHideTimer();
        return;
      }
      unawaited(c.togglePlay().then((_) => _publishNow('play-pause')));
    }
    _restartHideTimer();
  }

  void _showSeekPreview(Duration at) {
    setState(() => _seekPreview = at);
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekPreview = null);
    });
  }

  void _onLongPressStart(LongPressStartDetails d) {
    // 先判是不是按在弹幕上：命中就只点赞，不叠加长按 2 倍速。
    if (_tryLikeAt(d.globalPosition)) return;
    final PlayerController? c = _controller;
    if (c == null) return;
    _rateBeforeLongPress = c.rate;
    if (!_canControlLocally(c)) {
      _requestClaim('rate', rate: _longPressRate);
      return;
    }
    unawaited(c.setRate(_longPressRate).then((_) => _publishNow('rate')));
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    final PlayerController? c = _controller;
    if (c == null) return;
    if (!_canControlLocally(c)) {
      _requestClaim('rate', rate: _rateBeforeLongPress);
      return;
    }
    unawaited(c.setRate(_rateBeforeLongPress).then((_) => _publishNow('rate')));
  }

  void _onPanStart(DragStartDetails d) {
    _dragStart = d.localPosition;
    _mode = _DragMode.none;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final Size size = context.size ?? const Size(1, 1);
    final Offset total = d.localPosition - _dragStart;

    // 方向判定（12 §4.5）：先超过 6px 才认方向，避免斜着划来回抖
    if (_mode == _DragMode.none) {
      if (total.dx.abs() > 6 && total.dx.abs() > total.dy.abs()) {
        _mode = _DragMode.seek;
      } else if (total.dy.abs() > 6 && total.dy.abs() > total.dx.abs()) {
        _mode = _dragStart.dx < size.width / 2
            ? _DragMode.brightness
            : _DragMode.volume;
      } else {
        return;
      }
    }

    final PlayerController? c = _controller;
    if (c == null) return;

    switch (_mode) {
      case _DragMode.seek:
        // 拖动中只预览，松手才 seek（15 §A9 的坑）
        final double seconds = total.dx / size.width * _seekSpanSeconds;
        final Duration target = c.position + Duration(seconds: seconds.round());
        setState(() => _seekPreview = _clampToMedia(target, c.duration));
      case _DragMode.brightness:
        final double delta = -total.dy / size.height;
        final double base = _brightnessPreview ?? _originalBrightness ?? 0.5;
        final double v = (base + delta).clamp(0.02, 1.0);
        setState(() => _brightnessPreview = v);
        unawaited(_applyBrightness(v));
      case _DragMode.volume:
        final double delta = -total.dy / size.height;
        final double base = _volumePreview ?? _originalVolume ?? 0.5;
        final double v = (base + delta).clamp(0.0, 1.0);
        setState(() => _volumePreview = v);
        unawaited(_applyVolume(v));
      case _DragMode.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails _) {
    final PlayerController? c = _controller;
    if (_mode == _DragMode.seek && _seekPreview != null && c != null) {
      if (_canControlLocally(c)) {
        unawaited(c.seek(_seekPreview!));
        _publishNow('seek', at: _seekPreview);
        setState(() {
          _mode = _DragMode.none;
          _seekPreview = null;
        });
      } else {
        // 房主权威模式下：记下目标，统一由 _commitClaim 发帧；进度条先停在拖到的位置
        _pendingSeekTarget = _seekPreview;
        _commitClaim('pan');
        setState(() => _mode = _DragMode.none);
      }
      return;
    }
    setState(() {
      _mode = _DragMode.none;
      _seekPreview = null;
    });
  }

  static Duration _clampToMedia(Duration d, Duration total) {
    if (d < Duration.zero) return Duration.zero;
    if (total > Duration.zero && d > total) return total;
    return d;
  }

  Future<void> _applyBrightness(double v) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(v);
      // 13「亮度那条的正确验法」：回读窗口亮度，别用截图判断
      final double back = await ScreenBrightness().application;
      debugPrint('[YQK-BRIGHT] set=${v.toStringAsFixed(2)} '
          'readback=${back.toStringAsFixed(2)} '
          'appLevel=$_brightnessIsApplicationLevel');
    } on Object catch (e) {
      // 有的机型不允许应用级调亮度，忽略
      debugPrint('[YQK-BRIGHT] 设置失败：$e');
    }
  }

  Future<void> _applyVolume(double v) async {
    try {
      await VolumeController.instance.setVolume(v);
      final double back = await VolumeController.instance.getVolume();
      debugPrint('[YQK-VOLUME] apply=${v.toStringAsFixed(2)} '
          'readback=${back.toStringAsFixed(2)}');
    } on Object catch (e) {
      debugPrint('[YQK-VOLUME] 设置失败：$e');
    }
  }

  /// 客人进房起播：等房主快照里的片子，再 open → 等 duration → seek → play。
  Future<void> _openFromRoomSnapshot(PlayerController c) async {
    final RoomClient rc = widget.roomClient!;
    RoomSnapshot? snap = rc.snapshot.value;
    int waited = 0;
    while ((snap == null || snap.mediaUrl.isEmpty) && waited < 15000) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      waited += 200;
      if (!mounted) return;
      snap = rc.snapshot.value;
    }
    if (!mounted) return;
    if (snap == null || snap.mediaUrl.isEmpty) {
      setState(() => _openError = '房主还没选片');
      debugPrint('[YQK-ROOM] guest wait media timeout');
      return;
    }
    final RoomSnapshot s = snap;
    // 起播位置：取 hello/state 里的权威位置（有 state 时钟就用外推后的现值，
    // 拿不到才退回快照里那个进房瞬间的静态值）。以前这里只看快照，
    // 服务端 playback 又停在 0，于是客人永远从 0 秒起播。
    final Duration? auth = rc.authoritativePosition;
    final double authSec =
        auth == null ? 0 : auth.inMilliseconds / 1000.0;
    final double startSec = authSec > s.position ? authSec : s.position;
    debugPrint('[YQK-ROOM] guest open media url=<redacted> '
        'pos=${startSec.toStringAsFixed(1)} playing=${s.playing}');
    await c.open(
      PlayerMedia(
        id: s.mediaUrl,
        url: s.mediaUrl,
        title: s.mediaTitle.isEmpty ? '一起看' : s.mediaTitle,
        sourceKind: 'room',
      ),
      autoplay: false,
    );
    // 等 duration 就绪再 seek，否则 seek 会被丢掉
    int guard = 0;
    while (mounted && c.duration == Duration.zero) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (++guard > 100) break;
    }
    // 复用「open(play:false) → 等 duration → seek → play」这条既有链路，
    // 不在起播后再补一次 seek（那会跟跟随逻辑打架）
    await c.seek(Duration(milliseconds: (startSec * 1000).round()));
    if (s.playing) await c.play();
  }

  // ── 跟随播放（M7 定义性功能）────────────────────────────
  // 规则：房主是权威源、自己发的 state 不吞、拖动期间不响应、<2s 不动、
  // 暂停不外推位置；播放/暂停/倍速/换片都要跟。
  bool _seekingLocally = false;
  Timer? _seekSuppressTimer;
  /// 三档跟随里「变速追赶」的还原计时器：600ms 后必须回到 1.0。
  Timer? _speedRestore;

  /// 已发 claim、等房主答复。期间别人的 state 不应用（防被弹回），5 秒兜底。
  bool _awaitingClaim = false;

  /// 手势算出的待发目标：_seekPreview 只负责显示，这个只负责发帧
  Duration? _pendingSeekTarget;
  DateTime? _lastClaimAt;
  Timer? _awaitingTimer;

  /// 不在房间 / 没快照 / 自由共控 / 自己是房主 → 本地直接控
  bool _canControlLocally(PlayerController c) {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return true;
    final RoomSnapshot? s = rc.snapshot.value;
    if (s == null) return true;
    if (s.controlMode == 'free') return true;
    return _isRoomHost(c);
  }

  /// 请求房主授权（房主权威模式下非房主的所有控制手势都走这里）
  /// 手势/进度条算出的目标统一在这里发帧：_seekPreview 只管显示，_pendingSeekTarget 只管发
  void _commitClaim(String from) {
    final Duration? t = _pendingSeekTarget;
    if (t == null) return; // 正常路径不会走到，静默返回
    final DateTime now = DateTime.now();

    // pan 优先：横滑是用户在视频区的主动 seek；slider 那次是 swipe 穿过底部的副作用

    if (_lastClaimAt != null && now.difference(_lastClaimAt!).inMilliseconds < 50 && from != 'pan') return;

    _lastClaimAt = now;

    _pendingSeekTarget = null; // 发完立刻清，避免重复发
    _requestClaim('seek', position: t);
  }

  void _requestClaim(String action, {Duration? position, double? rate}) {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return;
    setState(() => _awaitingClaim = true);
    _awaitingTimer?.cancel();
    _awaitingTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _awaitingClaim = false);
    });
    final Map<String, dynamic> body = <String, dynamic>{
      'type': 'claim',
      'action': action,
    };
    if (action == 'seek') {
      // 拿不到目标就不发帧：release 里 assert 不执行，兜底值会把 bug 变成「静默跳到 0」
      final Duration? t = position;
      if (t == null) {
        debugPrint('[YQK-CLAIM] seek 缺少目标位置，丢弃');
        setState(() => _awaitingClaim = false);
        return;
      }
      body['position'] = t.inMilliseconds / 1000.0;
    } else if (action == 'rate') {
      final double? r = rate;
      if (r == null) {
        debugPrint('[YQK-CLAIM] rate 缺少倍速值，丢弃');
        setState(() => _awaitingClaim = false);
        return;
      }
      body['rate'] = r;
    }
    debugPrint('[YQK-CLAIM] tx body=${body.toString()}');
    rc.send(body);
    debugPrint('[YQK-CLAIM] send action=$action');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已请求房主'), duration: Duration(seconds: 2)),
      );
    }
  }

  /// 底部一句提示（失败也要有话说，不许静默）
  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  /// I-44：连接进了 closed（被踢 4005 / 房间关了 / 房主退房）就回首页。
  /// 以前这个状态没有任何 UI 消费方，被踢之后会停在一个空播放页上。
  void _onClientState(RoomClientState s) {
    if (s != RoomClientState.closed) return;
    if (_closedHandled || !mounted) return;
    _closedHandled = true;
    final String? notice = widget.roomClient?.kickNotice.value;
    debugPrint('[YQK-ROOM] closed → 回首页 notice=$notice');
    _snack(notice ?? '房间已关闭，先回首页');
    final NavigatorState? nav = Navigator.maybeOf(context);
    nav?.popUntil((Route<dynamic> r) => r.isFirst);
  }

  /// 昵称：拿不到就用「该成员」，别把 m_xxx 这种 id 甩给用户
  String _memberName(String id) {
    final String n = widget.roomClient?.snapshot.value?.memberById(id)?.nickname ?? '';
    return n.isEmpty ? '该成员' : n;
  }

  /// 禁言 / 解除禁言：等服务的 `muted` 帧回来再报成功（真被拒了要说实话）
  Future<void> _muteMember(String id, bool muted) async {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return;
    final String who = _memberName(id);
    final bool ok = await rc.setMuted(id, muted);
    debugPrint('[YQK-ROOM] setMuted member=$id muted=$muted ok=$ok');
    _snack(ok
        ? (muted ? '已禁言 $who' : '已解除禁言 $who')
        : (muted ? '禁言没成功，稍后再试' : '解除禁言没成功，稍后再试'));
  }

  /// 移出房间：帧发出去就算，服务端会广播 members 把这条摘掉
  void _kickMember(String id) {
    final RoomClient? rc = widget.roomClient;
    if (rc == null) return;
    final String who = _memberName(id);
    rc.send(<String, dynamic>{'type': 'kick', 'memberId': id});
    debugPrint('[YQK-ROOM] kick member=$id');
    _snack('已移出 $who');
  }

  /// 房主换人：提示一次（成为房主 / 房主已移交），控制条自己靠快照重建
  void _onHostNotice() {
    final String text = widget.roomClient?.hostNotice.value ?? '';
    if (text.isEmpty) return;
    debugPrint('[YQK-ROOM] hostNotice=$text');
    _snack(text);
    if (mounted) setState(() {});
  }

  void _onClaimResult() {
    final Map<String, dynamic>? j = widget.roomClient?.rejectedClaim.value;
    if (_awaitingClaim) {
      _awaitingTimer?.cancel();
      setState(() {
        _awaitingClaim = false;
        // 答复到了（无论批准还是拒绝）：清掉待确认的进度条位置
        _seekPreview = null;
      });
    }
    if (j == null || !mounted) return;
    final String reason = (j['reason'] as String?) ?? 'host';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason == 'timeout' ? '房主未响应' : '房主拒绝了'),
        duration: const Duration(seconds: 2),
      ),
    );
    debugPrint('[YQK-CLAIM] rejected reason=$reason');
  }

  void _beginLocalSeek() {
    _seekingLocally = true;
    _seekSuppressTimer?.cancel();
  }

  void _endLocalSeek(Duration target) {
    // 松手后 800ms 内不再接受远端 state，避免刚拖完就被弹回去
    _seekSuppressTimer?.cancel();
    _seekSuppressTimer = Timer(const Duration(milliseconds: 800), () {
      _seekingLocally = false;
    });
    _publishNow('seek', at: target);
  }

  void _reportMyProgress(Duration pos) {
    final RoomClient? rc = widget.roomClient;
    final PlayerController? c = _controller;
    if (rc == null || c == null) return;
    _lastPublishAt = DateTime.now();
    rc.send(<String, dynamic>{
      'type': 'progress',
      'position': pos.inMilliseconds / 1000.0,
      'playing': c.playing,
      // duration 一起报：服务端 playback.duration 一直是 0，
      // 客人那边进度条只能显示 00:00/00:00（Bug1 同一处根因的另一半）
      'duration': c.duration.inMilliseconds / 1000.0,
      'rate': c.rate,
    });
  }

  /// 房主操作完成立刻上报：claim 通道本来就是即时的，房主自己却要等
  /// 下一个 2 秒节拍才发帧（实测双机 3.0-3.1 秒），刚好反了 —— 房主才是权威源。
  ///
  /// 只在「本地能立刻生效」的分支里调（也就是房主）；客人走 claim，
  /// 这里调会和服务端权威打架。同步调用，不进任何定时器。
  void _publishNow(String why, {Duration? at}) {
    final PlayerController? c = _controller;
    if (!mounted || c == null) return;
    if (widget.roomClient == null) return;
    debugPrint('[YQK-PROGRESS] immediate why=$why');
    _lastPublishedPlaying = c.playing;
    _reportMyProgress(at ?? c.position);
  }

  Timer? _progressTimer;

  /// 上一次已经上报过的 playing 值：只在「播放态切换」时补一条
  /// （暂停那一刻的位置必须进 state，否则新客从最后一次播放位置起播）
  bool? _lastPublishedPlaying;

  /// free 模式下「非房主不上报」只提示一次，别每 2 秒刷屏
  bool _freeSkipLogged = false;

  /// 最近一次真正发出 progress 的时刻（只在 _reportMyProgress 里赋值）。
  /// 操作即上报之后，Timer 用它做 1.8s 节流：刚按完暂停/拖完进度条，
  /// 下一个节拍不再补一条一模一样的帧。
  DateTime? _lastPublishAt;

  /// 权威端每 2 秒报一次位置。
  ///
  /// 以前只在松手 seek 那一下报（_endLocalSeek），于是「一边播一边等客人进来」
  /// 这条最常见的路径上，服务端 room.playback.position 永远停在开播时的 0，
  /// 新客 hello 拿到的就是 0 → 从 0 秒起播、跟随条常驻「你领先 N 秒」。
  void _startProgressPublish() {
    _progressTimer?.cancel();
    if (widget.roomClient == null) return;
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (Timer _) {
      final PlayerController? c = _controller;
      if (!mounted || c == null) return;

      final DateTime now = DateTime.now();
      if (_lastPublishAt != null &&
          now.difference(_lastPublishAt!).inMilliseconds < 1800) {
        // 刚刚「操作即上报」过，这个节拍省掉，别补重复帧
        return;
      }

      // 上报者语义（管的是「谁能写权威位置」，和 _canControlLocally 的
      // 「本地能不能立刻生效」是两件事）：
      // free 模式下 4 个客人各报各的，playback.position 被交替覆盖、
      // seq 疯涨、跟随方位置来回跳。只留房主一个源，
      // 客人的位置由 claim 批准后的 state 广播带出去。
      final RoomSnapshot? s = widget.roomClient?.snapshot.value;
      final bool free = s != null && s.controlMode == 'free';
      if (free && !_isRoomHost(c)) {
        if (!_freeSkipLogged) {
          _freeSkipLogged = true;
          debugPrint('[YQK-PROGRESS] skip role=guest mode=free');
        }
        return;
      }
      // 房主权威模式：客人报上去服务端也不认，别白发帧
      if (!free && !_canControlLocally(c)) return;

      // playing 只读一次：读到一半被切换会让「切换判定」和「本次上报内容」错位
      final bool playing = c.playing;
      final bool switched = _lastPublishedPlaying != playing;
      if (switched) {
        // play→pause / pause→play：无条件补一条，暂停位置也要进 state
        _lastPublishedPlaying = playing;
        _reportMyProgress(c.position);
        return;
      }
      // 暂停稳态：位置不动，安静等下一次切换，不要每 2 秒刷一条一样的
      if (!playing) return;
      _reportMyProgress(c.position);
    });
  }

  void _onAuthoritative() => _applyAuthoritative();

  /// claim 被批准：服务端广播的 `by` 就是我自己，必须强制应用一次，
  /// 否则 shouldFollowState 的「自己发的不回灌」会把发起者跳过 → 他不动。
  void _onClaimGranted() => _applyAuthoritative(force: true);

  void _applyAuthoritative({bool force = false}) {
    final RoomClient? rc = widget.roomClient;
    final PlayerController? c = _controller;
    if (rc == null || c == null) return;

    // 实时状态只有一个来源：authoritative 三元组。
    // snapshot 是进房那一刻的快照（hello 的 room），永远停在 0 秒，不能当实时值。
    final Duration? authPos = rc.authoritativePosition;
    if (authPos == null) return;
    final bool playing = rc.authoritativePlaying;
    final double rate = rc.authoritativeRate;
    // authoritativePosition 已在 RoomClient 里按本地单调时钟外推过，这里不再外推
    final double target = authPos.inMilliseconds / 1000.0;

    // 等房主答复期间先不动（避免被别人的 state 弹回）；force 时例外
    if (_awaitingClaim && !force) {
      debugPrint('[YQK-FOLLOW] hold awaitingClaim (target=$target)');
      return;
    }

    final String me = rc.memberId ?? '';
    // 防自激：自己发的不回灌；房主在 host 模式是权威源，不跟别人（free 模式下房主也要跟）
    if (!force &&
        !shouldFollowState(
          me: me,
          by: rc.authoritativeBy,
          isHost: _isRoomHost(c),
          seekingLocally: _seekingLocally,
          freeMode: rc.snapshot.value?.controlMode == 'free',
        )) {
      if (_seekingLocally) debugPrint('[YQK-FOLLOW] skip: 正在本地拖动');
      return;
    }

    // 换片（只处理 URL 变了的情况）：URL 从 state 帧里取，不读 snapshot
    final String roomUrl = rc.authoritativeMediaUrl ?? '';
    final String curUrl = c.currentMedia?.url ?? '';
    if (roomUrl.isNotEmpty && roomUrl != curUrl) {
      debugPrint('[YQK-FOLLOW] media switch url=<redacted>');
      unawaited(_followSwitchMedia(c, roomUrl, target, playing));
      return;
    }

    if (playing != c.playing) {
      unawaited(playing ? c.play() : c.pause());
    }
    if ((rate - c.rate).abs() > 0.01) {
      unawaited(c.setRate(rate));
    }
    final double mine = c.position.inMilliseconds / 1000.0;
    // 13 号 D21 三档：<0.3s 不动 / 0.3–0.7s 变速追 / >=0.7s 硬跳。
    // 两档互斥：变速期间绝不 seek，seek 后也不再变速。
    final FollowAction act = decideFollow(target, mine);
    if (act == FollowAction.seek) {
      debugPrint('[YQK-FOLLOW] seek d=${(target - mine).toStringAsFixed(2)}');
      _speedRestore?.cancel();
      _speedRestore = null;
      unawaited(c.seek(Duration(milliseconds: (target * 1000).round())));
    } else if (act == FollowAction.speed) {
      final double r = catchUpRate(target, mine);
      debugPrint('[YQK-FOLLOW] speed d=${(target - mine).toStringAsFixed(2)} '
          'rate=${r.toStringAsFixed(3)}');
      unawaited(c.kernel.setProperty('speed', r.toStringAsFixed(3)));
      _speedRestore?.cancel();
      _speedRestore = Timer(const Duration(milliseconds: 600), () async {
        await c.kernel.setProperty('speed', '1.000');
        debugPrint('[YQK-FOLLOW] speed restore');
      });
    } else {
      debugPrint('[YQK-FOLLOW] none d=${(target - mine).toStringAsFixed(2)}');
    }
    debugPrint('[YQK-FOLLOW] apply playing=$playing '
        'pos=${target.toStringAsFixed(1)} rate=$rate '
        'by=${rc.authoritativeBy ?? '-'} '
        '(target=${target.toStringAsFixed(1)} mine=${mine.toStringAsFixed(1)})');
  }

  Future<void> _followSwitchMedia(
      PlayerController c, String url, double target, bool playing) async {
    try {
      final PlayerMedia next = PlayerMedia(
        id: url,
        url: url,
        title: '一起看',
        sourceKind: 'room',
      );
      await c.open(next, autoplay: false);
      await c.seek(Duration(milliseconds: (target * 1000).round()));
      if (playing) await c.play();
      debugPrint('[YQK-FOLLOW] media switched ok');
    } on Object catch (e) {
      debugPrint('[YQK-FOLLOW] media switch failed: $e');
    }
  }

  // ── 全屏 ────────────────────────────────────────────────
  Future<void> _toggleFullscreen() async {
    final bool next = !_fullscreen;
    if (kDebugMode) {
      debugPrint('[YQK-FS] tap -> next=$next');
    }
    setState(() => _fullscreen = next);
    if (next) {
      // 转屏/沉浸失败不能把全屏整个废掉：退化成竖屏全屏（画面铺满，不再按比例算矩形）
      try {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[YQK-FS] orientation not applied, fallback portrait-fullscreen: $e');
        }
      }
    } else {
      try {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[YQK-FS] restore orientation failed: $e');
        }
      }
    }
    _restartHideTimer();
  }

  // ── 弹层 ────────────────────────────────────────────────
  Future<void> _showRateSheet() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    const List<double> rates = <double>[0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.videoBar,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: Text('播放速度', style: TextStyle(color: AppColors.videoText)),
            ),
            for (final double r in rates)
              ListTile(
                title: Text(
                  formatRate(r),
                  style: TextStyle(
                    color: r == c.rate
                        ? AppColors.primaryEnd
                        : AppColors.videoText,
                  ),
                ),
                trailing: r == c.rate
                    ? Icon(Icons.check, color: AppColors.primaryEnd)
                    : null,
                onTap: () {
                  unawaited(c.setRate(r).then((_) => _publishNow('rate')));
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
    _restartHideTimer();
  }

  // ── 设置（05 §3.2 的「设置」入口）─────────────────────────
  // 只放**当场能看到效果**的项：倍速、字幕延迟、字幕字号。
  // 画质档位已按 04 §12.6.2 撤掉（本机 scale 改不出像素差，给选择器就是骗人）。
  Future<void> _showSettingsSheet() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    const List<double> rates = <double>[0.75, 1.0, 1.25, 1.5, 2.0];
    const List<double> fontSizes = <double>[36, 42, 48, 56];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.videoBar,
      builder: (BuildContext ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.all(AppSpace.md),
                child:
                    Text('设置', style: TextStyle(color: AppColors.videoText)),
              ),
              _sheetLabel('播放速度  当前 ${formatRate(c.rate)}'),
              Wrap(
                spacing: AppSpace.sm,
                children: <Widget>[
                  for (final double r in rates)
                    _sheetChip(
                      label: formatRate(r),
                      selected: (c.rate - r).abs() < 0.001,
                      onTap: () {
                        unawaited(
                            c.setRate(r).then((_) => _publishNow('rate')));
                      },
                    ),
                ],
              ),
              // 15 §A8：>2.0 音调补偿会失真，提前说清楚，别让用户以为坏了
              if (c.rate > 2.0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                      AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('当前倍速偏高，声音可能有杂音',
                        style: TextStyle(
                            color: AppColors.videoDim, fontSize: 12)),
                  ),
                ),
              // 自动连播（03 §6 autoPlayNext，默认开）
              SwitchListTile(
                value: c.autoNext,
                onChanged: (bool v) => unawaited(c.setAutoNext(v)),
                title: const Text('自动连播下一集',
                    style: TextStyle(color: AppColors.videoText, fontSize: 14)),
                activeThumbColor: AppColors.primaryEnd,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpace.md),
              ),
              // H4：跳过片头 / 片尾（默认关 —— 自动跳是「惊喜变惊吓」的典型）
              SwitchListTile(
                value: _skipIntro,
                onChanged: (bool v) => unawaited(_setSkipIntro(v)),
                title: const Text('跳过片头',
                    style: TextStyle(color: AppColors.videoText, fontSize: 14)),
                subtitle: Text(
                    (_chapMark?.introEnd ?? -1) > 0
                        ? '片头结束 ${MediaChapter.short(_chapMark!.introEnd)}（从菜单「章节与片头片尾」改）'
                        : '还没标片头结束，可在「章节与片头片尾」里标',
                    style:
                        const TextStyle(color: AppColors.videoDim, fontSize: 12)),
                activeThumbColor: AppColors.primaryEnd,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpace.md),
              ),
              SwitchListTile(
                value: _skipOutro,
                onChanged: (bool v) => unawaited(_setSkipOutro(v)),
                title: const Text('跳过片尾',
                    style: TextStyle(color: AppColors.videoText, fontSize: 14)),
                subtitle: Text(
                    (_chapMark?.outroStart ?? -1) > 0
                        ? '片尾开始 ${MediaChapter.short(_chapMark!.outroStart)}（到点提示，不自动切）'
                        : '还没标片尾开始，可在「章节与片头片尾」里标',
                    style:
                        const TextStyle(color: AppColors.videoDim, fontSize: 12)),
                activeThumbColor: AppColors.primaryEnd,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpace.md),
              ),
              if (c.supportsSubtitleTuning) ...<Widget>[
                _sheetLabel('字幕延迟  ${c.subDelay.toStringAsFixed(1)}s'),
                Row(
                  children: <Widget>[
                    _sheetChip(
                      label: '−0.5s',
                      selected: false,
                      onTap: () => unawaited(
                          c.setSubDelay(c.subDelay - 0.5)),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _sheetChip(
                      label: '复位',
                      selected: c.subDelay.abs() < 0.001,
                      onTap: () => unawaited(c.setSubDelay(0)),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _sheetChip(
                      label: '+0.5s',
                      selected: false,
                      onTap: () => unawaited(
                          c.setSubDelay(c.subDelay + 0.5)),
                    ),
                  ],
                ),
                _sheetLabel('字幕字号  ${c.subFontSize.round()}'),
                Wrap(
                  spacing: AppSpace.sm,
                  children: <Widget>[
                    for (final double s in fontSizes)
                      _sheetChip(
                        label: s.round().toString(),
                        selected: (c.subFontSize - s).abs() < 0.001,
                        onTap: () => unawaited(c.setSubFontSize(s)),
                      ),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.md, AppSpace.sm, AppSpace.md, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${c.kernel.name} 内核不支持调字幕延迟，切回 mpv 可用',
                      style:
                          const TextStyle(color: AppColors.videoDim, fontSize: 12),
                    ),
                  ),
                ),
              // 请求头编辑（本轮 10 号）：任意键值对都能加 / 删 / 改，
              // 保存后当场按当前位置重播，不用退出页面
              ListTile(
                leading:
                    const Icon(Icons.tune, color: AppColors.videoDim),
                title: const Text('请求头',
                    style:
                        TextStyle(color: AppColors.videoText, fontSize: 14)),
                subtitle: Text(
                  '当前 ${c.currentMedia?.headers.length ?? 0} 条 · 可加删改任意键值，保存即重播',
                  style:
                      const TextStyle(color: AppColors.videoDim, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_showHeadersEditor(c));
                },
              ),
              // 高级面板只在 debug 构建里给（05 §3.2 / 15 §A11）
              if (kDebugMode)
                ListTile(
                  leading: const Icon(Icons.developer_mode,
                      color: AppColors.videoDim),
                  title: const Text('高级面板（调试构建）',
                      style: TextStyle(
                          color: AppColors.videoText, fontSize: 14)),
                  subtitle: const Text('内核属性、切内核、导出日志',
                      style:
                          TextStyle(color: AppColors.videoDim, fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(context.push(Routes.playerAdvanced, extra: c));
                  },
                ),
              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
      ),
    );
    _restartHideTimer();
  }

  /// 请求头编辑器（本轮 10 号）：一行一个键值对，可加、可改、可删。
  /// 保存后写进 HeaderStore（按站点记忆）并立刻按当前位置重播。
  Future<void> _showHeadersEditor(PlayerController c) async {
    final PlayerMedia? media = c.currentMedia;
    if (media == null) return;
    final HeaderStore store = HeaderStore();
    final String host = Uri.tryParse(media.url)?.host ?? '';
    // 现有规则 + 当前片子的 headers 合并作为初值
    final Map<String, String> initial = <String, String>{
      ...media.headers,
      ...await store.headersFor(media.url),
    };
    final List<MapEntry<String, String>> rows =
        initial.entries.toList(growable: true);
    if (rows.isEmpty) rows.add(const MapEntry<String, String>('Referer', ''));

    if (!mounted) return;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        String hostValue = host;
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setLocal) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text('请求头', style: TextStyle(color: AppColors.text)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text('生效站点',
                              style: TextStyle(
                                  color: AppColors.textSub, fontSize: 12)),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: TextFormField(
                              initialValue: hostValue,
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: '留空 = 所有站点',
                              ),
                              onChanged: (String v) => hostValue = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      for (int i = 0; i < rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.xs),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                flex: 4,
                                child: TextFormField(
                                  initialValue: rows[i].key,
                                  decoration: const InputDecoration(
                                      isDense: true, hintText: '键，如 Referer'),
                                  onChanged: (String v) => rows[i] =
                                      MapEntry<String, String>(v, rows[i].value),
                                ),
                              ),
                              const SizedBox(width: AppSpace.xs),
                              Expanded(
                                flex: 5,
                                child: TextFormField(
                                  initialValue: rows[i].value,
                                  decoration: const InputDecoration(
                                      isDense: true, hintText: '值'),
                                  onChanged: (String v) => rows[i] =
                                      MapEntry<String, String>(rows[i].key, v),
                                ),
                              ),
                              IconButton(
                                tooltip: '删掉这一条',
                                icon: Icon(Icons.remove_circle_outline,
                                    color: AppColors.danger, size: 20),
                                onPressed: () => setLocal(() => rows.removeAt(i)),
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('加一条'),
                          onPressed: () => setLocal(
                            () => rows.add(const MapEntry<String, String>('', '')),
                          ),
                        ),
                      ),
                      Text(
                        '保存后会立刻按当前位置重播，不用退出页面',
                        style: TextStyle(color: AppColors.textDim, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('保存并重播'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true) {
      _restartHideTimer();
      return;
    }

    final Map<String, String> headers = <String, String>{};
    for (final MapEntry<String, String> row in rows) {
      final String k = row.key.trim();
      final String v = row.value.trim();
      if (k.isEmpty) continue; // 空键直接忽略，不塞脏数据
      headers[k] = v;
    }
    // 按站点记住，下次同一个站点的地址自动带上
    await store.put(host, headers);
    await c.reopenWithHeaders(headers);
    if (mounted) _showNotice('请求头已保存，正在用新请求头重播');
    _restartHideTimer();
  }

  Widget _sheetLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(color: AppColors.videoDim, fontSize: 12)),
        ),
      );

  Widget _sheetChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: AppSpace.xs),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryEnd : AppColors.surface3,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.textOn : AppColors.text,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );

  Future<void> _showSubtitleSheet() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    final List<String> tracks = c.kernel.subtitleTrackNames;
    final String? mediaUrl = c.media?.url;
    final List<SubtitleRow> subs = (mediaUrl == null || _db == null)
        ? const <SubtitleRow>[]
        : await _db!.subtitleDao.byMedia(mediaUrl);
    debugPrint('[YQK-SUB] menu url=$mediaUrl db=${subs.length} '
        'embedded=${tracks.length}');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.videoBar,
      // 默认最大高度只有 9/16 屏，字幕条目一多「选外挂字幕文件」就被裁掉，
      // 所以放开高度上限，再自己用 ConstrainedBox 收在 0.72 屏内。
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        // 库里的字幕 + 内嵌轨 + 手动选文件，条目会随片子变多；给个上限并允许滚动，
        // 不然「选外挂字幕文件」会被挤出屏幕（vivo 1080x2400 实测过）。
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text(L.of(context).playerSubtitle, style: const TextStyle(color: AppColors.videoText)),
            ),
            ListTile(
              title: const Text('关闭字幕',
                  style: TextStyle(color: AppColors.videoText)),
              onTap: () {
                unawaited(c.setSubtitle(null));
                Navigator.of(ctx).pop();
              },
            ),
            // F12 字幕库：先列库里这个片子的字幕（最近用的在前）
            for (final SubtitleRow r in subs)
              ListTile(
                leading: const Icon(Icons.subtitles_outlined,
                    color: AppColors.videoText),
                title: Text(r.label,
                    style: const TextStyle(color: AppColors.videoText)),
                subtitle: Text(
                  '${r.lang} · ${r.format}'
                  '${r.lastUsedAt > 0 ? ' · 用过' : ''}',
                  style:
                      const TextStyle(color: AppColors.videoDim, fontSize: 12),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_applySubtitleRow(c, r));
                },
              ),
            for (int i = 0; i < tracks.length; i++)
              ListTile(
                title: Text(tracks[i],
                    style: const TextStyle(color: AppColors.videoText)),
                onTap: () {
                  unawaited(c.kernel.setSubtitleTrack(i));
                  Navigator.of(ctx).pop();
                },
              ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined,
                  color: AppColors.videoText),
              title: const Text('选外挂字幕文件',
                  style: TextStyle(color: AppColors.videoText)),
              subtitle: const Text(
                '支持 .srt / .ass / .vtt；GBK 编码的 SRT 会自动转成 UTF-8',
                style: TextStyle(color: AppColors.videoDim, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_pickSubtitleFile());
              },
            ),
            if (c.subtitleSource != null)
              ListTile(
                title: Text('字幕延迟 ${c.subDelay.toStringAsFixed(1)}s'
                    ' · 字号 ${c.subFontSize.round()}',
                    style: const TextStyle(color: AppColors.videoText)),
                subtitle: const Text(
                  '左右点按微调：-0.5s / +0.5s，字号 -2 / +2',
                  style: TextStyle(color: AppColors.videoDim, fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.remove,
                          color: AppColors.videoText),
                      onPressed: () {
                        unawaited(c.setSubDelay(c.subDelay - 0.5));
                        Navigator.of(ctx).pop();
                        _showSubtitleSheet();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.videoText),
                      onPressed: () {
                        unawaited(c.setSubDelay(c.subDelay + 0.5));
                        Navigator.of(ctx).pop();
                        _showSubtitleSheet();
                      },
                    ),
                  ],
                ),
              ),
          ],
                ),
              ),
            ),
          ),
    );
    _restartHideTimer();
  }

  /// 选一个外挂字幕文件：GBK 的 SRT 会先转 UTF-8 再交给 mpv（15 §A5）
  Future<void> _pickSubtitleFile() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    try {
      // file_picker 13：静态方法，返回 List<PlatformFile>，空列表=用户取消
      final List<PlatformFile> picked = await FilePicker.pickFiles(
        dialogTitle: '选字幕文件',
        type: FileType.custom,
        allowedExtensions: <String>['srt', 'ass', 'ssa', 'vtt'],
      );
      if (picked.isEmpty) {
        debugPrint('[YQK-SUB] pick cancel');
        return;
      }
      final PlatformFile file = picked.first;
      final String? path = file.path;
      debugPrint('[YQK-SUB] pick name=${file.name} path=$path');
      if (path == null || path.isEmpty) {
        debugPrint('[YQK-SUB] pick no local path (content uri?)');
        return;
      }
      await c.setSubtitle(path, label: file.name);
      await _loadSubtitleData(path);
      debugPrint('[YQK-SUB] pick applied label=${file.name} path=$path');
      // F12：手动关联的字幕也进字幕库，下次不用再翻文件
      final String? mediaUrl = c.media?.url;
      final AppDatabase? db = _db;
      if (mediaUrl != null && db != null) {
        final String ext = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : 'srt';
        final String lang = SubtitleScanner.langOf(file.name);
        await db.subtitleDao.upsert(SubtitlesCompanion.insert(
          id: _subId(mediaUrl, lang, path),
          mediaUrl: mediaUrl,
          label: file.name,
          addedAt: DateTime.now().millisecondsSinceEpoch,
          lang: Value<String>(lang),
          path: Value<String?>(path),
          format: Value<String>(ext),
        ));
      }
    } on Object {
      if (!mounted) return;
      setState(() => _openError = '这个字幕文件读不了，换一个试试');
    }
  }

  /// 选一个外挂音轨文件（13 §A6′）：挂成第二条音轨后由用户在列表里选
  Future<void> _pickExternalAudio() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    if (c.kernelKind != KernelKind.mpv) {
      _showNotice('外挂音轨只有 mpv 内核支持，先切回 mpv');
      return;
    }
    try {
      final List<PlatformFile> picked = await FilePicker.pickFiles(
        dialogTitle: '选音频文件',
        type: FileType.custom,
        allowedExtensions: <String>['ogg', 'mp3', 'm4a', 'aac', 'flac', 'wav'],
      );
      if (picked.isEmpty) return;
      final PlatformFile file = picked.first;
      final String? path = file.path;
      if (path == null || path.isEmpty) return;
      await c.addExternalAudio(path, label: file.name);
      if (!mounted) return;
      _showNotice('已挂上外挂音轨，在音轨列表里选它');
    } on Object catch (e) {
      debugPrint('[YQK-AUDIOFILE] 选择/挂载失败：$e');
      if (!mounted) return;
      _showNotice('这个音频文件挂不上，换一个试试');
    }
  }

  Future<void> _showAudioSheet() async {
    final PlayerController? c = _controller;
    if (c == null) return;
    final List<AudioTrackInfo> tracks = c.audioTracks;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.videoBar,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: Text('音轨', style: TextStyle(color: AppColors.videoText)),
            ),
            ListTile(
              leading: const Icon(Icons.library_music_outlined,
                  color: AppColors.videoText),
              title: const Text('挂外挂音轨',
                  style: TextStyle(color: AppColors.videoText)),
              subtitle: Text(
                c.externalAudioLabel == null
                    ? '选一个本地音频文件当第二条音轨（mpv 内核）'
                    : '已挂：',
                style: const TextStyle(color: AppColors.videoDim),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_pickExternalAudio());
              },
            ),
            for (int i = 0; i < tracks.length; i++)
              ListTile(
                title: Text(tracks[i].label,
                    style: const TextStyle(color: AppColors.videoText)),
                subtitle: tracks[i].language == null
                    ? null
                    : Text('语言 ${tracks[i].language}',
                        style: const TextStyle(color: AppColors.videoDim)),
                trailing: i == c.audioTrackIndex
                    ? Icon(Icons.check, color: AppColors.primaryEnd)
                    : null,
                onTap: () {
                  unawaited(c.setAudioTrack(i));
                  Navigator.of(ctx).pop();
                },
              ),
            if (tracks.length <= 1)
              const ListTile(
                title: Text('这条流只有一条音轨',
                    style: TextStyle(color: AppColors.videoDim)),
              ),
          ],
        ),
      ),
    );
    _restartHideTimer();
  }

  // ── UI ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final PlayerController? c = _controller;
    if (kDebugMode) {
      debugPrint('[YQK-FS] build fullscreen=$_fullscreen '
          'size=${MediaQuery.sizeOf(context)}');
    }

    // 全屏时返回键先退出全屏，不直接 pop 页面（不靠 adb 坐标点 chip）
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        if (_fullscreen) {
          debugPrint('[YQK-FS] back -> exit fullscreen');
          setState(() => _fullscreen = false);
          unawaited(SystemChrome.setPreferredOrientations(
              <DeviceOrientation>[DeviceOrientation.portraitUp]));
          unawaited(
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.videoBg,
      // 键盘不替我们缩 body：竖屏那段自己按 viewInsets 让位，
      // 否则 Scaffold 缩一次、Column 再让一次，说话条会离键盘半屏远（见 L3.png）。
      resizeToAvoidBottomInset: false,
      body: c == null
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primaryEnd),
            )
          : _fullscreen
              ? Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Center(
                  child: AspectRatio(
                    aspectRatio: _aspectRatio(c),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        c.kernel.buildVideo(
                          fit: c.aspect.stretch ? BoxFit.fill : BoxFit.contain,
                        ),
                        // 弹幕在字幕下面：字幕是刚需，弹幕是氛围（压住字幕就废了）
                        DanmakuOverlay(
                          controller: c,
                          danmakus: widget.roomClient?.danmakus,
                          settings: _dm,
                        ),
                        // 字幕自绘：mpv 的 OSD 层在 Android 上画不出来（15 §A5 四步排查）
                        if (_subData != null)
                          Positioned.fill(
                            child: SubtitleOverlay(controller: c, data: _subData!),
                          ),
                        // 房间浮层放在手势层之上（见下面 Positioned.fill 那段），
                        // 这里不再重复挂一份，否则会出现两层浮层叠在一起。
                      ],
                    ),
                  ),
                ),
                _gestureLayer(c),
                _hud(c),
                _controlsLayer(c),
                // 房间浮层必须叠在手势层之上，否则三块浮层收不到点击
                // （上一版放在视频内部 Stack，被 _gestureLayer 全屏吞掉）。
                // 这里用同一个 aspectRatio 再算一次视频矩形，浮层就贴着画面走。
                if (widget.roomClient != null)
                  Positioned.fill(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _aspectRatio(c),
                        child: Stack(
                          children: <Widget>[
                            // 全屏只留右上角胶囊（N 人在看）+ 房主锁定按钮，
                            // 其余浮层收起来别挡画面（784×360 上一条 44 高的条会吃掉 12%）
                            // G4：横屏大屏（>=600 且宽>高）时这两个东西改成右侧**竖排**，
                            // 免得横排压住 16:9 画面右上角的字幕；判据用 LayoutBuilder 的
                            // 约束，不用 MediaQuery（含系统栏，横屏时会抖）。
                            if (_fullscreen)
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (BuildContext ctx,
                                      BoxConstraints cons) {
                                    final bool wide = isWideLandscape(
                                        cons.maxWidth, cons.maxHeight);
                                    if (wide) {
                                      logScreenClass(
                                          'player-fullscreen', cons.maxWidth);
                                      debugPrint(
                                          '[YQK-UI] player rail=right '
                                          'w=${cons.maxWidth.toStringAsFixed(1)} '
                                          'h=${cons.maxHeight.toStringAsFixed(1)}');
                                    }
                                    final Widget pill =
                                        RoomFullscreenPillBody(
                                            snapshot: widget
                                                .roomClient!.snapshot);
                                    final Widget? lock = _isRoomHost(c)
                                        ? FullscreenHostLock(
                                            snapshot:
                                                widget.roomClient!.snapshot,
                                            onControlMode: (String mode) =>
                                                widget.roomClient!
                                                    .send(<String, dynamic>{
                                              'type': 'settings',
                                              'control_mode': mode,
                                            }),
                                          )
                                        : null;
                                    return Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            top: 8, right: 10),
                                        child: wide
                                            // 竖排：胶囊在上、房主锁在下，整列贴右边
                                            ? Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: <Widget>[
                                                  pill,
                                                  if (lock != null) ...<Widget>[
                                                    const SizedBox(height: 6),
                                                    lock,
                                                  ],
                                                ],
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                  pill,
                                                  if (lock != null) ...<Widget>[
                                                    const SizedBox(width: 6),
                                                    lock,
                                                  ],
                                                ],
                                              ),
                                      ),
                                    );
                                  },
                                ),
                              )
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_openError != null) _errorBanner(_openError!),
              ],
            )
              : _portraitBody(c),
      ),
    );
  }

  /// 竖屏分区：视频在上，房间浮层排在视频**下面**。
  ///
  /// 之前成员条 / 房主条 / 说话条全浮在视频 Stack 里，86 逻辑高会跟播放控制条
  /// 抢同一块地（room1.png 里输入框压住进度条）。这里按屏幕高度先算视频区，
  /// 剩下的交给房间区，谁也别压谁。
  Widget _portraitBody(PlayerController c) {
    final double ratio = _aspectRatio(c);
    final double kb = MediaQuery.viewInsetsOf(context).bottom;
    final double statusH = MediaQuery.of(context).padding.top;
    final bool hasRoom = widget.roomClient != null;
    final RoomSnapshot? snap = widget.roomClient?.snapshot.value;
    final bool iAmHost = snap != null &&
        (snap.memberById(widget.roomClient!.memberId ?? '')?.isOwner ?? false);

    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        final double usableH = cons.maxHeight - kb - statusH;
        // 房间区固定高度：成员条 44 + 房主/跟随条 56 + 说话条 48 + 上下内边距 12
        final double barH = hasRoom ? 44 : 0;
        final double hostH = hasRoom && iAmHost ? 44 : 0;
        final double chatH = hasRoom ? 48 : 0;
        final double roomH = barH + hostH + chatH + 12;
        // 房间内视频最多 55%（剩下给成员条 + 聊天区）；
        // 单机播放吃满可用高度，否则下面会空出一大半
        final double maxVideo = hasRoom ? usableH * 0.55 : usableH;
        final double videoH =
            math.min(math.min(cons.maxWidth / ratio, maxVideo), usableH - roomH);
        final double total = videoH + roomH;
        // 值没变就不打：同一次布局里 build 可能被调两次（20:52:12.810 / .877），
        // 256 KiB 的日志缓冲下这些重复行会把验收需要的 YQK-DM trace 挤掉。
        final String layoutKey = '${videoH.toStringAsFixed(1)}/'
            '${roomH.toStringAsFixed(1)}/${usableH.toStringAsFixed(1)}';
        if (kDebugMode && layoutKey != _lastLayoutKey) {
          _lastLayoutKey = layoutKey;
          debugPrint('[YQK-LAYOUT] video=${videoH.toStringAsFixed(1)} '
              'bar=${barH.toStringAsFixed(1)} chat=${chatH.toStringAsFixed(1)} '
              'total=${total.toStringAsFixed(1)} screen=${usableH.toStringAsFixed(1)} '
              'kb=$kb overflow=${total > usableH}');
        }
        assert(total <= usableH + 0.5,
            '[YQK-LAYOUT] 溢出：total=$total screen=$usableH');

        return Padding(
          // 键盘弹起时整块往上让；顶部让开状态栏（edgeToEdge 下不给会被系统栏压住）
          padding: EdgeInsets.only(top: statusH, bottom: kb),
          child: Column(
            // 单机播放：画面上下黑边等高（垂直居中）；房间内仍从上往下排
            mainAxisAlignment:
                hasRoom ? MainAxisAlignment.start : MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                // 房间内只占 videoH（下面留给成员条+聊天）；
                // 单机播放撑满，视频靠 Center 居中，顶栏底栏贴屏幕边互不重叠
                height: hasRoom ? videoH : usableH,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // 画面按比例居中，别让 Texture 撑满整个盒子（否则会被裁掉上下）
                    Center(
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            c.kernel.buildVideo(
                              fit: c.aspect.stretch ? BoxFit.fill : BoxFit.contain,
                            ),
                            // D20 第三步：屏幕共享整块盖住视频区，但在弹幕层之下。
                            // ValueKey(track.id) 保证换轨时重建 renderer，不复用旧纹理。
                            if (_remoteScreen != null)
                              Positioned.fill(
                                child: ScreenView(
                                  key: ValueKey<String>(_remoteScreen!.id ?? ''),
                                  track: _remoteScreen!,
                                ),
                              ),
                            // 弹幕在字幕下面（Stack 顺序：视频 → 共享屏 → 弹幕 → 字幕）
                            // 点赞数变化要重画「+N」：监听 rc.danmakuLikes 重新 build 这一层，
                            // 不动弹幕表本身（_items 由 overlay 自己订阅）。
                            if (widget.roomClient == null)
                              DanmakuOverlay(controller: c, settings: _dm)
                            else
                              ValueListenableBuilder<Map<String, int>>(
                                valueListenable: widget.roomClient!.danmakuLikes,
                                builder: (BuildContext context,
                                    Map<String, int> likes, Widget? child) {
                                  return DanmakuOverlay(
                                    key: _dmLayerKey,
                                    controller: c,
                                    danmakus: widget.roomClient?.danmakus,
                                    settings: _dm,
                                    likes: likes,
                                    onDanmakuLike: _likeDanmaku,
                                    onHitBoxes: (List<({String id, Rect rect})> b) {
                                      _dmRects = b;
                                    },
                                  );
                                },
                              ),
                            // 字幕自绘：mpv 的 OSD 层在 Android 上画不出来（15 §A5 四步排查）
                            if (_subData != null)
                              Positioned.fill(
                                child: SubtitleOverlay(
                                    controller: c, data: _subData!),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _gestureLayer(c),
                    _hud(c),
                    _controlsLayer(c),
                    // 房主才有：别人请求控制权时贴视频区下沿的一条（bottom:8 落在黑边里，
                    // top:48 会压住 ⏪⏸⏩）。必须叠在控制层之上，否则被控制条吞掉点击。
                    if (hasRoom && iAmHost)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: ValueListenableBuilder<Map<String, dynamic>?>(
                          valueListenable: widget.roomClient!.pendingClaim,
                          builder: (BuildContext ctx,
                              Map<String, dynamic>? claim, Widget? _) {
                            final String? rid = claim?['rid'] as String?;
                            debugPrint('[YQK-CLAIM] bar build rid=$rid');
                            // 服务端只把 claim-result 回给**发起者**，房主自己点了允许/忽略
                            // 之后本地 pendingClaim 仍是那条，条子会挂着不动（实测停在 ·0s）。
                            // 这里按 rid 记一笔已处理，重新 build 时直接不渲染。
                            if (rid != null && rid == _claimDismissedRid) {
                              return const SizedBox.shrink();
                            }
                            return ClaimBar(
                              claim: claim,
                              onAllow: (Map<String, dynamic> cl) {
                                setState(() {
                                  _claimDismissedRid = cl['rid'] as String?;
                                });
                                widget.roomClient!.send(<String, dynamic>{
                                  'type': 'control',
                                  'action': cl['action'],
                                  't': cl['position'],
                                  'rid': cl['rid'],
                                });
                              },
                              onIgnore: (Map<String, dynamic> cl) {
                                setState(() {
                                  _claimDismissedRid = cl['rid'] as String?;
                                });
                                widget.roomClient!.send(<String, dynamic>{
                                  'type': 'claim-result',
                                  'rid': cl['rid'],
                                  'ok': false,
                                  'reason': 'host',
                                });
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              if (hasRoom) ...<Widget>[
                // 房间条（成员 / 跟随 / 房主）统一铺在 App 背景色上：
                // 以前直接压在 Scaffold 的 videoBg（近黑）上，视频下面会留一大块黑条
                ColoredBox(
                  color: AppColors.bg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _voiceMemberBar(embedded: true),
                      RoomFollowBar(
                  snapshot: widget.roomClient!.snapshot,
                  memberId: widget.roomClient!.memberId,
                  isHost: iAmHost,
                  expected: () => widget.roomClient!.expectedPosition,
                  myPosition: () => c.position,
                  onSeek: (Duration d) => c.seek(d),
                  embedded: true,
                ),
                if (iAmHost)
                  RoomHostBar(
                    snapshot: widget.roomClient!.snapshot,
                    memberId: widget.roomClient!.memberId,
                    embedded: true,
                    onDanmakuSettings: _openDanmakuSettings,
                    onBotConfig: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BotConfigPage(roomClient: widget.roomClient!),
                      ),
                    ),
                    onWebWatch: _openWebWatch,
                    onPickMedia: _pickMediaForRoom,
                    onScreenShare: _toggleScreenShare,
                    screenSharingActive: _screen?.active ?? false,
                    onCastDlna: _castToDlna,
                    onLocalMedia: _openLocalMedia,
                    onReplay: _openRoomReplay,
                  onDebugSendDanmaku: kDebugMode ? _sendDebugDanmaku : null,
                  onDebugSendTrio: kDebugMode ? _sendDebugDanmakuTrio : null,
                    onControlMode: (String mode) =>
                        widget.roomClient!.send(<String, dynamic>{
                      'type': 'settings',
                      'control_mode': mode,
                    }),
                    onTransfer: (String id) =>
                        widget.roomClient!.send(<String, dynamic>{
                      'type': 'setHost',
                      'memberId': id,
                    }),
                    onKick: (String id) => _kickMember(id),
                    onMute: (String id, bool muted) => _muteMember(id, muted),
                  ),
                    ],
                  ),
                ),
                // 房间消息列表（M8：接 chats 真数据；弹幕/表情留到下一步）
                Expanded(
                  child: RoomMessageList(
                    client: widget.roomClient!,
                    memberId: widget.roomClient!.memberId ?? '',
                  ),
                ),
                _voiceChatBar(embedded: true),
              ] else
                const Expanded(child: SizedBox.expand()),
              if (_openError != null) _errorBanner(_openError!),
            ],
          ),
        );
      },
    );
  }

  /// M2 先按 16:9 占位。真实视频宽高要从内核事件里带出来（M3），
  /// 现在 Video 的 fit 已经 contain，比例不对也只是多留黑边、不会裁画面。
  /// 容器比例 = 画面比例。
  /// 之前这里硬写 16/9（M2 的占位），非 16:9 片源会让字幕坐标整体偏移：
  /// 容器比画面宽 → 字幕左右各多一截黑边；比画面窄 → 字幕挤进画面外。
  /// fill（拉伸）也必须返回画面比例，否则 BoxFit.fill 会在错容器里被拉两次。
  double _aspectRatio(PlayerController c) {
    final double? va = c.videoAspect;
    final double ratio = switch (c.aspect) {
      AspectMode.original => (va != null && va > 0) ? va : 16 / 9,
      AspectMode.r16x9 => 16 / 9,
      AspectMode.r4x3 => 4 / 3,
      // 填充：容器必须是 16:9 才能把画面拉到满屏；容器=画面比例时 BoxFit.fill 等价 contain（拉伸量为 0）
      AspectMode.fill => 16 / 9,
    };
    if (kDebugMode) {
      debugPrint(
        '[YQK-ASPECT] mode=${c.aspect.name} videoAspect=${va?.toStringAsFixed(4) ?? 'null'} '
        'ratio=${ratio.toStringAsFixed(4)}',
      );
    }
    return ratio;
  }

  /// 打不开时的人话提示（七条 MUST：失败必须有人话文案）
  Widget _errorBanner(String text) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 96, left: AppSpace.md, right: AppSpace.md),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.videoBar,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.videoText, fontSize: 13.5),
          ),
        ),
      ),
    );
  }

  Widget _gestureLayer(PlayerController c) {    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          debugPrint('[YQK-CTRL] gesture tap visible=$_controlsVisible');
          _toggleControls();
        },
        onDoubleTapDown: _onDoubleTapDown,
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: const ColoredBox(color: Colors.transparent),
      ),
    );
  }

  /// 手势提示浮层：进度预览 / 亮度条 / 音量条
  Widget _hud(PlayerController c) {
    if (_seekPreview != null) {
      return IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.videoBar,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              '${formatDuration(_seekPreview!)} / ${formatDuration(c.duration)}',
              style: const TextStyle(
                color: AppColors.videoText,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    final double? percent = _mode == _DragMode.brightness
        ? _brightnessPreview
        : (_mode == _DragMode.volume ? _volumePreview : null);
    if (percent == null) return const SizedBox.shrink();

    final bool isBrightness = _mode == _DragMode.brightness;
    return IgnorePointer(
      child: Align(
        alignment:
            isBrightness ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          child: Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.videoBar,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isBrightness ? Icons.brightness_6 : Icons.volume_up,
                  color: AppColors.videoText,
                  size: 20,
                ),
                const SizedBox(height: AppSpace.xs),
                SizedBox(
                  height: 120,
                  width: 6,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: LinearProgressIndicator(
                      value: percent,
                      backgroundColor: AppColors.videoDim,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryEnd,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${(percent * 100).round()}',
                  style: const TextStyle(
                    color: AppColors.videoText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlsLayer(PlayerController c) {
    // 05 §3.2：显隐必须用 AnimatedOpacity，换 AnimatedSwitcher 会重建视频树导致 mpv 纹理闪黑
    // P1b：顶栏/底栏隐藏时保持透明但**可点**（点一下就生效，不用点两下）；
    //      只有中间三个大圆在隐藏时必须不可点，否则点画面会误触暂停。
    return Stack(
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: _fade,
            curve: Curves.easeOut,
            child: _topBar(c),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: _fade,
            curve: Curves.easeOut,
            child: _bottomBar(c),
          ),
        ),
        IgnorePointer(
          ignoring: !_controlsVisible,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: _fade,
            curve: Curves.easeOut,
            child: Center(child: _centerBar(c)),
          ),
        ),
      ],
    );
  }

  Widget _topBar(PlayerController c) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.videoBar, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + AppSpace.xs,
        left: AppSpace.xs,
        right: AppSpace.sm,
        bottom: AppSpace.xl,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.videoText),
            onPressed: () {
              debugPrint('[YQK-CTRL] tap back visible=$_controlsVisible');
              Navigator.of(context).maybePop();
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.media?.title ?? widget.media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.videoText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (c.media?.episodeIndex != null)
                  Text(
                    '第 ${(c.media!.episodeIndex! + 1)} 集',
                    style: const TextStyle(
                      color: AppColors.videoDim,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: _favOn ? '取消收藏' : '收藏',
            icon: Icon(_favOn ? Icons.star : Icons.star_border,
                color: AppColors.videoText),
            onPressed: () => unawaited(_toggleFav()),
          ),
          // A 组：稍后看 / 下载本片（和星标共用 favorites 表，tag='later' 区分）
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert, color: AppColors.videoText),
            onSelected: (String v) {
              switch (v) {
                case 'fav':
                  unawaited(_toggleFav());
                case 'later':
                  unawaited(_toggleLater());
                case 'follow':
                  unawaited(_toggleFollow());
                case 'download':
                  unawaited(_downloadThis());
                case 'dmlib':
                  unawaited(_openDanmakuLibrary());
                case 'toplaylist':
                  unawaited(_addToPlaylist());
                case 'replay':
                  _openRoomReplay();
                case 'chapters':
                  unawaited(_showChapterSheet());
              }
              _restartHideTimer();
            },
            itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'fav',
                child: Text(_favOn ? '取消收藏' : '收藏'),
              ),
              PopupMenuItem<String>(
                value: 'later',
                child: Text(_laterOn ? '移出稍后看' : '稍后看'),
              ),
              PopupMenuItem<String>(
                value: 'follow',
                child: Text(_followOn ? '取消追番' : '追番'),
              ),
              const PopupMenuItem<String>(
                value: 'download',
                child: Text('下载本片'),
              ),
              const PopupMenuItem<String>(
                value: 'dmlib',
                child: Text('弹幕库'),
              ),
              const PopupMenuItem<String>(
                value: 'toplaylist',
                child: Text('加入列表…'),
              ),
              // H11：房间回放（只有真的在房间里才有内容）
              if (widget.roomClient != null)
                const PopupMenuItem<String>(
                  value: 'replay',
                  child: Text('本房间回放'),
                ),
              // H4：章节与手动片头片尾
              const PopupMenuItem<String>(
                value: 'chapters',
                child: Text('章节与片头片尾'),
              ),
            ],
          ),
          if (c.hasPrev)
            IconButton(
              tooltip: '上一集',
              icon: const Icon(Icons.skip_previous, color: AppColors.videoText),
              onPressed: () {
                unawaited(c.previous().then((_) => _publishNow('episode')));
                _restartHideTimer();
              },
            ),
          if (c.hasNext)
            IconButton(
              tooltip: '下一集',
              icon: const Icon(Icons.skip_next, color: AppColors.videoText),
              onPressed: () {
                unawaited(c.next().then((_) => _publishNow('episode')));
                _restartHideTimer();
              },
            ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.tune, color: AppColors.videoText),
            onPressed: () {
              debugPrint('[YQK-CTRL] tap tune visible=$_controlsVisible');
              _showSettingsSheet();
            },
          ),
        ],
      ),
    );
  }

  Widget _centerBar(PlayerController c) {
    return FocusTraversalGroup(
      // G3：D-pad 左右键在 ⏪ / ⏸ / ⏩ 之间走，顺序按视觉从左到右
      policy: ReadingOrderTraversalPolicy(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _roundIcon(Icons.replay_10, () {
            unawaited(c.seekBy(const Duration(seconds: -10)));
            _restartHideTimer();
          }),
          const SizedBox(width: AppSpace.xl),
          _bigPlayPause(c),
          const SizedBox(width: AppSpace.xl),
          _roundIcon(Icons.forward_10, () {
            unawaited(c.seekBy(const Duration(seconds: 10)));
            _restartHideTimer();
          }),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.videoBar,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.videoText),
        onPressed: onTap,
      ),
    );
  }

  Widget _bigPlayPause(PlayerController c) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.videoBar,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        iconSize: 64,
        // G3：控制条一出现焦点就落在播放/暂停上，遥控器按 OK 直接播/停
        autofocus: true,
        icon: Icon(
          c.playing ? Icons.pause : Icons.play_arrow,
          color: AppColors.videoText,
        ),
        onPressed: () {
          if (!_canControlLocally(c)) {
            _requestClaim(c.playing ? 'pause' : 'play');
            _restartHideTimer();
            return;
          }
          unawaited(c.togglePlay().then((_) => _publishNow('play-pause')));
          _restartHideTimer();
        },
      ),
    );
  }

  Widget _bottomBar(PlayerController c) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[AppColors.videoBar, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        left: AppSpace.md,
        right: AppSpace.md,
        bottom: MediaQuery.of(context).padding.bottom + AppSpace.xs,
        top: AppSpace.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                formatDuration(c.position),
                style: const TextStyle(
                  color: AppColors.videoText,
                  fontSize: 12,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                // 待房主确认期间整条进度条半透明：用户看到「停在 05:00 但还没生效」
                child: Opacity(
                  opacity: _awaitingClaim ? 0.6 : 1,
                  child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: _awaitingClaim
                        ? AppColors.primaryEnd.withValues(alpha: 0.6)
                        : AppColors.primaryEnd,
                    inactiveTrackColor: AppColors.videoDim,
                    thumbColor: _awaitingClaim
                        ? AppColors.primaryEnd.withValues(alpha: 0.6)
                        : AppColors.primaryEnd,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: c.progress,
                    onChangeStart: (_) {
                      _hideTimer?.cancel();
                      _beginLocalSeek();
                    },
                    onChanged: (double v) {
                      // 拖动时只挪 UI，不 seek；松手才跳（跟手势一致）
                      setState(() => _seekPreview = Duration(
                            milliseconds:
                                (c.duration.inMilliseconds * v).round(),
                          ));
                    },
                    onChangeEnd: (double v) {
                      final Duration target = Duration(
                        milliseconds: (c.duration.inMilliseconds * v).round(),
                      );
                      if (!_canControlLocally(c)) {
                        // 待确认期间保留 _seekPreview（进度条停在拖到的位置），_onClaimResult 里再清
                        _pendingSeekTarget = target;
                        setState(() => _seekPreview = target);
                        _commitClaim('slider');
                        _restartHideTimer();
                        return;
                      }
                      unawaited(c.seek(target));
                      setState(() => _seekPreview = null);
                      _endLocalSeek(target);
                      _restartHideTimer();
                    },
                  ),
                ),
                ),
              ),
              Text(
                formatDuration(c.duration),
                style: const TextStyle(
                  color: AppColors.videoText,
                  fontSize: 12,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          // 底栏 chips：字幕挂了长文件名时一行放不下，改成可横滑，避免 RenderFlex 溢出条纹
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: Row(
              children: <Widget>[
              _bottomChip(formatRate(c.rate), _showRateSheet),
              _bottomChip(
                c.subtitleLabel ?? L.of(context).playerSubtitle,
                _showSubtitleSheet,
                active: c.subtitleLabel != null,
              ),
              _bottomChip('音轨', _showAudioSheet),
              // 15 §A7：原始 / 16:9 / 4:3 / 填充，点一下循环
              _bottomChip(
                c.aspect.label,
                () {
                  unawaited(c.cycleAspect());
                  _restartHideTimer();
                },
                active: c.aspect != AspectMode.original,
              ),
              _bottomChip(_fullscreen ? '退出全屏' : L.of(context).playerFullscreen, _toggleFullscreen),
              _bottomChip('设置', _showSettingsSheet),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomChip(String label, VoidCallback onTap, {bool active = false}) {
    return TextButton(
      onPressed: () {
        // P1a 验收：确认底栏按钮真的收到了点击（行为不变，只打日志）
        debugPrint('[YQK-CTRL] tap $label visible=$_controlsVisible');
        onTap();
      },
      style: TextButton.styleFrom(
        foregroundColor: active ? AppColors.primaryEnd : AppColors.videoText,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xxs,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      // 标签可能是长文件名，限宽 + 省略号，别把行撑爆
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 96),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}