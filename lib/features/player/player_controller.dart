import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../data/db/app_database.dart';
import '../../data/local/prefs.dart';
import '../../platform/player/kernel_factory.dart';
import '../../platform/player/mpv_kernel.dart';
import '../../platform/player/playback_kernel.dart';
import '../../platform/player/subtitle_loader.dart';

/// 一部片子的最小描述：播放解耦用这个，不依赖数据层实体（03 §2.1 依赖方向）。
@immutable
class PlayerMedia {
  const PlayerMedia({
    required this.id,
    required this.title,
    required this.url,
    this.sourceKind = 'local',
    this.sourceId,
    this.poster,
    this.episodeIndex,
    this.seriesId,
    this.headers = const <String, String>{},
    this.playlist = const <PlayerMedia>[],
  });

  /// 历史表主键（同一个片子换源也复用这个 id，续播才连续）
  final String id;
  final String title;
  final String url;
  final String sourceKind;
  final String? sourceId;
  final String? poster;
  final int? episodeIndex;
  final String? seriesId;

  /// 防盗链请求头（不放 Cookie 到日志）
  final Map<String, String> headers;

  /// 这条片子所属的整条片单（MacCMS 一条线路的剧集）；空表示单集
  final List<PlayerMedia> playlist;

  PlayerMedia copyWithUrl(String newUrl) => PlayerMedia(
        id: id,
        title: title,
        url: newUrl,
        sourceKind: sourceKind,
        sourceId: sourceId,
        poster: poster,
        episodeIndex: episodeIndex,
        seriesId: seriesId,
        headers: headers,
      );

  /// 只换请求头，地址与片单都不动（编辑请求头后立即重播用）
  PlayerMedia copyWithHeaders(Map<String, String> newHeaders) => PlayerMedia(
        id: id,
        title: title,
        url: url,
        sourceKind: sourceKind,
        sourceId: sourceId,
        poster: poster,
        episodeIndex: episodeIndex,
        seriesId: seriesId,
        headers: newHeaders,
        playlist: playlist,
      );
}

/// 画面比例四档（15 §A7）：原始 / 16:9 / 4:3 / 填充。
enum AspectMode {
  original('原始'),
  r16x9('16:9'),
  r4x3('4:3'),
  fill('填充');

  const AspectMode(this.label);

  final String label;

  /// 给内核的比例值：<=0 表示用源比例
  double get ratio {
    switch (this) {
      case AspectMode.original:
      case AspectMode.fill:
        return -1;
      case AspectMode.r16x9:
        return 16 / 9;
      case AspectMode.r4x3:
        return 4 / 3;
    }
  }

  /// 「填充」靠拉伸铺满，其余保持比例
  bool get stretch => this == AspectMode.fill;

  AspectMode get next =>
      AspectMode.values[(index + 1) % AspectMode.values.length];
}

/// 播放控制（12 §4 / 15 §A12）。
///
/// 只做四件事：转发给内核、攒播放状态、**每 5 秒把进度写进 history**、
/// 内核出问题时按 12 §4.4 兜底。watched_seconds 的增量一律由
/// [HistoryDao.record] 算，这里不自己算（M1 定的唯一入口）。
class PlayerController extends ChangeNotifier {
  PlayerController({
    PlaybackKernel? kernel,
    required this.history,
    this.prefs,
    SubtitleLoader? subtitles,
    this.persistInterval = defaultPersistInterval,
  })  : _kernel = kernel ?? MpvKernel(),
        // 外部注入内核（单测）就不再走工厂，免得不小心换掉
        _kernelInjected = kernel != null,
        _subtitles = subtitles ?? SubtitleLoader() {
    _bind();
  }

  /// 12 §4：播放中每 5 秒写一次进度
  static const Duration defaultPersistInterval = Duration(seconds: 5);

  /// 第 40 轮：open 的全局递增号，日志里用 seq= 把 enter/fail/done 串成一组
  static int _openSeq = 0;

  /// 15 §A8：倍速区间 0.25–4.0，超出即夹断
  static const double minRate = 0.25;
  static const double maxRate = 4.0;

  /// 15 §A12：小于 5 秒算没看过
  static const double resumeMinSeconds = 5;

  /// 片尾 10 秒内算看完（与 HistoryDao 的 _finishedTailSeconds 一致）
  static const double finishedTailSeconds = 10;

  /// 12 §4.4：开播 5 秒内报错才算「内核起不来」，过了这个点就是片子/网络问题
  static const Duration fallbackWindow = Duration(seconds: 5);

  final HistoryDao history;
  final Prefs? prefs;
  final SubtitleLoader _subtitles;
  final Duration persistInterval;

  PlaybackKernel _kernel;
  final bool _kernelInjected;
  KernelKind _kind = KernelKind.mpv;
  bool _triedFallback = false;
  DateTime? _openedAt;
  /// 开播那一刻（比 _openedAt 早：_openedAt 是 open 成功之后才写）
  DateTime? _openStartedAt;

  /// 4 号必修：同一次播放只原地重试 1 次
  bool _replayedOnce = false;
  /// 重试进行中：error 事件可能连发两次，别让第二次插队
  bool _retrying = false;

  /// 起播延后判据：播放器没 ready 时先等，最多等 10 秒（不许做成永远不判）
  static const Duration deferReadyTimeout = Duration(seconds: 10);
  bool _ready = false;
  bool _deferTimerFired = false;
  String? _deferredError;
  Timer? _deferTimer;

  /// 二次失败 → 直链判定失效，页面负责 invalidate + 刷新
  void Function(PlayerMedia media, String message)? onFatal;

  final StreamController<String> _notices = StreamController<String>.broadcast();

  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  Timer? _persistTimer;

  PlayerMedia? _media;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  double _rate = 1.0;
  String? _error;
  String? _subtitlePath;
  String? _subtitleLabel;
  String? _externalAudio;
  double _subDelay = 0;
  double _subFontSize = 42;
  AspectMode _aspect = AspectMode.original;
  bool _disposed = false;

  /// 片单（上一集/下一集/自动连播，15 §A3）
  List<PlayerMedia> _playlist = const <PlayerMedia>[];
  int _playlistIndex = -1;

  PlayerMedia? get media => _media;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get buffering => _buffering;
  double get rate => _rate;
  String? get error => _error;
  String? get subtitleLabel => _subtitleLabel;
  double get subDelay => _subDelay;
  double get subFontSize => _subFontSize;
  AspectMode get aspect => _aspect;

  PlaybackKernel get kernel => _kernel;

  /// 画面显示比例（宽/高）。未知时为 null，调用方自己退 16:9。
  double? get videoAspect => _kernel.videoAspect;
  KernelKind get kernelKind => _kind;

  /// 一次性提示（内核降级之类），界面只弹一条，不打断观看
  Stream<String> get notices => _notices.stream;

  List<AudioTrackInfo> get audioTracks => _kernel.audioTracks;
  int get audioTrackIndex => _kernel.currentAudioTrack;
  bool get supportsSubtitleTuning => _kernel.supportsSubtitleTuning;

  bool get hasPrev => _playlistIndex > 0;
  bool get hasNext =>
      _playlistIndex >= 0 && _playlistIndex < _playlist.length - 1;
  int get playlistIndex => _playlistIndex;
  int get playlistLength => _playlist.length;

  /// 当前片单（只读）。第 38 轮换片源广播要把整条线路带给客人。
  List<PlayerMedia> get playlist => _playlist;

  /// 自动连播（03 §6 autoPlayNext，默认开）
  bool get autoNext => prefs?.getBool(PrefKeys.autoPlayNext) ?? true;
  Future<void> setAutoNext(bool value) async {
    await prefs?.setBool(PrefKeys.autoPlayNext, value);
    notifyListeners();
  }

  /// 第 40 轮：离房时把 autoNext 恢复成进房前的值。
  /// 此刻 controller 往往已经 dispose，不能再用 setAutoNext（它的 notifyListeners
  /// 会抛「used after being disposed」），只写 pref、不通知。
  Future<void> persistAutoNextQuiet(bool value) async {
    await prefs?.setBool(PrefKeys.autoPlayNext, value);
  }

  /// 进度比例（0–1），进度条用
  double get progress {
    if (_duration <= Duration.zero) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
  }

  // ── 片单 ────────────────────────────────────────────────
  /// 设置片单（播放页进来时调一次）。[currentId] 用来定位当前集。
  void setPlaylist(List<PlayerMedia> items, {String? currentId}) {
    _playlist = List<PlayerMedia>.unmodifiable(items);
    final String? id = currentId ?? _media?.id;
    _playlistIndex = id == null
        ? -1
        : _playlist.indexWhere((PlayerMedia m) => m.id == id);
  }

  Future<void> next() async {
    if (!hasNext) return;
    debugPrint('[YQK-PLAYLIST] 下一集：$_playlistIndex -> ${_playlistIndex + 1}');
    await _openAt(_playlistIndex + 1);
  }

  Future<void> previous() async {
    if (!hasPrev) return;
    debugPrint('[YQK-PLAYLIST] 上一集：$_playlistIndex -> ${_playlistIndex - 1}');
    await _openAt(_playlistIndex - 1);
  }

  Future<void> _openAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _playlistIndex = index;
    final PlayerMedia m = _playlist[index];
    await open(m, start: Duration.zero);
  }

  // ── 打开 / 续播 ─────────────────────────────────────────
  /// 打开一个媒体。
  ///
  /// [start] 传了就按它；没传先查历史决定是不是要续播（15 §A12）。
  /// 当前正在播的片子（换请求头重播要用）
  PlayerMedia? get currentMedia => _media;

  /// 改完请求头立刻生效（本轮 10 号要求：不许「保存后重进页面才生效」）。
  ///
  /// 做法是不重建播放器、只按当前位置重开同一条地址：mpv 的
  /// `http-header-fields` 只在 open 时读，所以必须重开一次；
  /// 位置带上，用户看到的是同一秒。
  Future<void> reopenWithHeaders(Map<String, String> headers) async {
    final PlayerMedia? media = _media;
    if (media == null) return;
    final Duration at = _position;
    final double rate = _rate;
    final PlayerMedia withHeaders = media.copyWithHeaders(headers);
    await open(withHeaders, start: at, rate: rate);
    debugPrint('[YQK-HEADERS] 改完立刻重播：pairs=${headers.length} '
        'at=${at.inMilliseconds}ms');
  }

  Future<void> open(
    PlayerMedia media, {
    Duration? start,
    bool autoplay = true,
    double? rate,
  }) async {
    // 第 40 轮定位用：同一条 media 可能被连开多次（切集/降级/重试），
    // 用递增 seq 把 enter / fail / done 串成一组，才能看清是哪一次炸的
    final int seq = ++_openSeq;
    final String openUrl =
        media.url.length > 60 ? media.url.substring(0, 60) : media.url;
    debugPrint('[YQK-OPEN] enter seq=$seq id=${media.id} url=$openUrl');

    // 换源前先把上一条的进度落盘，否则"切集"会丢掉刚看的那几分钟
    await flushProgress();

    // 首次打开按 pref 选内核；注入内核的单测直接用注进来的那个
    if (!_kernelInjected && _media == null) {
      await _prepareKernelFromPrefs();
    }

    _media = media;
    _error = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    if (_playlist.isNotEmpty) {
      final int i = _playlist.indexWhere((PlayerMedia m) => m.id == media.id);
      if (i >= 0) _playlistIndex = i;
    }

    _openStartedAt = DateTime.now();
    // 直播没有进度可续：seek 会报 '--force-seekable=yes'，这里一律从头播
    final bool isLive = media.sourceKind.contains('live');
    final Duration at =
        isLive ? Duration.zero : (start ?? await resumeStart(media));

    try {
      await _kernel.open(
        media.url,
        options: MediaOpenOptions(headers: media.headers),
        start: at,
        play: autoplay,
      );
    } on Object catch (err) {
      debugPrint('[YQK-OPEN] fail seq=$seq id=${media.id} '
          'kernel=${_kind.name} err=$err');
      // 12 §4.4：非 mpv 内核连打都打不开（典型是 fvp 的 so 没带上）→ 立刻降回 mpv 重开，
      // 界面只出一条轻提示，不把用户丢在错误页上
      if (_kernelInjected ||
          _triedFallback ||
          _kind == KernelKind.mpv) {
        rethrow;
      }
      debugPrint('[YQK-KERNEL] ${_kind.label} 打开失败：$err → 降回 mpv');
      _notices.add('${_kind.label} 起不来，已切回 mpv 播放');
      _triedFallback = true;
      await _unbind();
      final PlaybackKernel old = _kernel;
      _kernel = MpvKernel();
      _kind = KernelKind.mpv;
      _bind();
      unawaited(old.dispose());
      await _kernel.open(
        media.url,
        options: MediaOpenOptions(headers: media.headers),
        start: at,
        play: autoplay,
      );
    }
    _openedAt = DateTime.now();
    debugPrint('[YQK-OPEN] done seq=$seq id=${media.id} '
        'state=${_kind.name}:playing=${_kernel.playing}'
        ':pos=${_kernel.position.inMilliseconds}ms'
        ':dur=${_kernel.duration.inMilliseconds}ms');
    // 每次成功开播都重置「已原地重试」标记：一条片子给一次重试机会
    _replayedOnce = false;
    // 每条片子重新算 ready / 延后判据
    _ready = false;
    _deferTimerFired = false;
    _deferredError = null;
    _deferTimer?.cancel();

    if (_kernel.supportsProperties) {
      // 15 §A8：变速不变调
      await _kernel.setProperty('audio-pitch-correction', 'yes');
    }

    await setRate(rate ?? _readRatePref());
    if (_aspect != AspectMode.original) {
      await _kernel.setAspectRatio(_aspect.ratio);
    }

    _persistTimer?.cancel();
    _persistTimer = Timer.periodic(persistInterval, (Timer _) {
      unawaited(flushProgress());
    });
    _notify();
  }

  double _readRatePref() {
    final double? saved = prefs?.getDouble(PrefKeys.playbackSpeed);
    if (saved == null) return _rate;
    return saved.clamp(minRate, maxRate).toDouble();
  }

  /// 续播起点：position 在 (5, duration-10) 区间才续，否则从头
  Future<Duration> resumeStart(PlayerMedia media) async {
    final History? h = await history.byId(media.id);
    if (h == null) return Duration.zero;

    // 用户可以在设置里关掉续播（03 §6 continueFromLast，默认开）
    final bool enabled = prefs?.getBool(PrefKeys.continueFromLast) ?? true;
    if (!enabled) return Duration.zero;

    final double pos = h.position;
    if (pos <= resumeMinSeconds) return Duration.zero;
    if (h.duration > 0 && pos >= h.duration - finishedTailSeconds) {
      return Duration.zero;
    }
    return Duration(milliseconds: (pos * 1000).round());
  }

  // ── 内核装配与兜底 ──────────────────────────────────────
  Future<void> _prepareKernelFromPrefs() async {
    final KernelKind wanted = KernelFactory.fromPref(prefs);
    await _installKernel(wanted, reopen: false);
  }

  /// 装一个内核并接上事件流。fvp 起不来就退回 mpv（12 §4.4）。
  Future<void> _installKernel(KernelKind wanted,
      {required bool reopen}) async {
    final KernelKind resolved = KernelFactory.resolve(wanted);
    PlaybackKernel next;
    try {
      next = KernelFactory.create(resolved);
      _kind = resolved;
    } on Object catch (err) {
      // 造不出来（缺 so / MDK 初始化失败）→ 记一条日志 + 退回 mpv
      debugPrint('[YQK-KERNEL] ${resolved.prefValue} 创建失败：$err');
      _notices.add('${resolved.label} 内核起不来，已用 mpv 播放');
      next = MpvKernel();
      _kind = KernelKind.mpv;
    }
    await _unbind();
    final PlaybackKernel old = _kernel;
    _kernel = next;
    _bind();
    if (!identical(old, next)) unawaited(old.dispose());
    if (reopen && _media != null) {
      await open(_media!, start: _position, autoplay: true);
    }
    _notify();
  }

  /// 用户/高级面板手动切内核
  Future<void> setKernelKind(KernelKind kind) async {
    await prefs?.setString(PrefKeys.kernelKind, kind.prefValue);
    _triedFallback = false;
    await _installKernel(kind, reopen: _media != null);
  }

  void _bind() {
    _subs.addAll(<StreamSubscription<Object?>>[
      _kernel.positionStream.listen(_onPosition),
      _kernel.durationStream.listen(_onDuration),
      _kernel.playingStream.listen(_onPlaying),
      _kernel.bufferingStream.listen(_onBuffering),
      _kernel.errorStream.listen(_onError),
      _kernel.events.listen(_onEvent),
    ]);
  }

  Future<void> _unbind() async {
    for (final StreamSubscription<Object?> s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  /// 12 §4.4：开播 5 秒内出错 → 降回 mpv 重开，只提示一次
  Future<void> _maybeFallback(String message) async {
    if (_kernelInjected || _triedFallback) return;
    if (_kind == KernelKind.mpv) return;
    final DateTime? t = _openedAt;
    if (t == null) return;
    if (DateTime.now().difference(t) > fallbackWindow) return;

    _triedFallback = true;
    final PlayerMedia? m = _media;
    final Duration pos = _position;
    debugPrint('[YQK-KERNEL] ${_kind.label} 开播失败：$message → 降回 mpv');
    _notices.add('${_kind.label} 播不了这个片子，已切回 mpv');

    await _unbind();
    final PlaybackKernel old = _kernel;
    _kernel = MpvKernel();
    _kind = KernelKind.mpv;
    _bind();
    unawaited(old.dispose());

    if (m != null) {
      _media = m;
      await open(m, start: pos, autoplay: true);
    }
    _notify();
  }

  // ── 播放控制 ────────────────────────────────────────────
  Future<void> play() => _kernel.play();
  Future<void> pause() async {
    await _kernel.pause();
    // 15 §A12：暂停也要落一次
    await flushProgress();
  }

  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> seek(Duration d) async {
    final Duration target = d < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && d > _duration ? _duration : d);
    await _kernel.seek(target);
    _position = target;
    _notify();
  }

  Future<void> seekBy(Duration delta) => seek(_position + delta);

  /// 倍速：夹在 0.25–4.0（15 §A8），并记住（03 §6 playbackSpeed）
  Future<void> setRate(double value) async {
    final double r = value.clamp(minRate, maxRate).toDouble();
    _rate = r;
    await _kernel.setRate(r);
    await prefs?.setDouble(PrefKeys.playbackSpeed, r);
    // 回读一次，证明真写进内核了（验收 A8′ 要这一行）
    // mpv 的倍速属性名是 speed（不是 rate），两个都读出来
    final Map<String, String?> back =
        await _kernel.debugProperties(const <String>['speed', 'rate']);
    debugPrint('[YQK-RATE] set=${r}x readback speed=${back['speed']} rate=${back['rate']} '
        'pitch=${await _kernel.readProperty('audio-pitch-correction')}');
    _notify();
  }

  /// 画面比例：四档循环（15 §A7）
  Future<void> cycleAspect() => setAspect(_aspect.next);

  /// 三档交给 mpv（原始/16:9/4:3），「填充」纯 Flutter 拉伸、不碰 mpv
  /// （15 §A7 2026-11-06 真机结论：media_kit 的 Video 是 Texture，
  /// 输出恒为源分辨率，keepaspect/panscan/aspect-override=0 都改不了几何）
  Future<void> setAspect(AspectMode mode) async {
    _aspect = mode;
    if (!mode.stretch) {
      await _kernel.setAspectRatio(mode.ratio);
    }
    final Map<String, String?> back =
        await _kernel.debugProperties(const <String>['video-aspect-override']);
    debugPrint('[YQK-ASPECT] mode=${mode.label} stretch=${mode.stretch} '
        'write=${mode.stretch ? '(不写 mpv)' : mode.ratio} '
        'readback=${back['video-aspect-override']}');
    _notify();
  }

  // ── 字幕 ────────────────────────────────────────────────
  /// 挂外挂字幕 / 关字幕。
  ///
  /// [source] 可以是本地 SRT/ASS 路径、file:// 或 http(s) 字幕；
  /// GBK 的会先转 UTF-8 再交给内核（15 §A5）。
  Future<void> setSubtitle(String? source, {String? label}) async {
    if (source == null || source.trim().isEmpty) {
      await _kernel.setSubtitle(null);
      _subtitlePath = null;
      _subtitleLabel = null;
      _notify();
      return;
    }
    final String path = await _subtitles.prepare(source.trim());
    await _kernel.setSubtitle(path, title: label);
    await _kernel.setSubDelay(_subDelay);
    await _kernel.setSubFontSize(_subFontSize);
    _subtitlePath = path;
    _subtitleLabel = label ?? '外挂字幕';
    // 15 §A5：GBK 的 SRT 会先转成 UTF-8 再挂，这里把落地路径打出来
    debugPrint('[YQK-SUB] 已挂字幕 label=$_subtitleLabel '
        'src=$source -> path=$path');
    _notify();
  }

  String? get subtitleSource => _subtitlePath;

  Future<void> setSubDelay(double seconds) async {
    _subDelay = seconds;
    await _kernel.setSubDelay(seconds);
    _notify();
  }

  Future<void> setSubFontSize(double size) async {
    _subFontSize = size;
    await _kernel.setSubFontSize(size);
    _notify();
  }

  Future<void> setAudioTrack(int index) async {
    // 15 §A6：切音轨就是写 aid；写完回读一次，确认真的生效
    final Map<String, String?> before =
        await _kernel.debugProperties(const <String>['aid']);
    await _kernel.setAudioTrack(index);
    final Map<String, String?> after =
        await _kernel.debugProperties(const <String>['aid']);
    debugPrint('[YQK-AID] ${_kernel.name} 选中第 ${index + 1} 条：'
        'aid ${before['aid']} -> ${after['aid']}');
    _notify();
  }

  /// 验收专用：把一组 mpv 属性原样写进去（只走深链 subprops，UI 不暴露）。
  /// 15 §A5 的四步排查靠它逐条试，不用每次重编。
  Future<void> applyRawProperties(Map<String, String> props) async {
    for (final MapEntry<String, String> e in props.entries) {
      await _kernel.setProperty(e.key, e.value);
      final String? back = await _kernel.readProperty(e.key);
      debugPrint('[YQK-SUBPROP] ${e.key}=${e.value} readback=$back');
    }
  }
  /// 外挂音轨（15 §A6 / 13 §A6′）：把本地音频挂成第二条音轨，再让用户选
  Future<void> addExternalAudio(String path, {String? label}) async {
    // 13 A6：换轨前先记下当前 aid，挂上外挂音轨后 mpv 会自动切过去，日志要能看出 1 -> 2
    final Map<String, String?> aidBefore =
        await _kernel.debugProperties(const <String>['aid']);
    await _kernel.addExternalAudio(path);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final Map<String, String?> aidAfter =
        await _kernel.debugProperties(const <String>['aid']);
    debugPrint('[YQK-AID] ${_kernel.name} 外挂音轨：'
        'aid ${aidBefore['aid']} -> ${aidAfter['aid']}');
    _externalAudio = label ?? path.split(Platform.pathSeparator).last;
    // mpv 挂上 audio-file 之后 track-list 会多一条，重新读一遍给弹层用
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final List<AudioTrackInfo> tracks = _kernel.audioTracks;
    debugPrint('[YQK-AUDIOFILE] 外挂音轨已就绪 label=$_externalAudio '
        'tracks=${tracks.length}');
    for (int i = 0; i < tracks.length; i++) {
      debugPrint('[YQK-AUDIOFILE] track[$i] label=${tracks[i].label} '
          'lang=${tracks[i].language} ch=${tracks[i].channels}');
    }
    // 外挂音轨挂在 track-list 最后：让内核自己挑最后一条（写 aid）
    final Map<String, String?> before =
        await _kernel.debugProperties(const <String>['aid']);
    await _kernel.selectLastAudioTrack();
    // mpv 改 aid 是异步的，等一拍再回读
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final Map<String, String?> after =
        await _kernel.debugProperties(const <String>['aid']);
    debugPrint('[YQK-AID] ${_kernel.name} 选中外挂音轨：'
        'aid ${before['aid']} -> ${after['aid']}');
    _notify();
  }

  String? get externalAudioLabel => _externalAudio;

  // ── 进度落盘 ────────────────────────────────────────────
  /// 把当前进度写进 history（走 [HistoryDao.record]，增量由它算）
  Future<void> flushProgress() async {
    final PlayerMedia? m = _media;
    if (m == null) return;
    if (_duration <= Duration.zero) return; // 还没拿到时长，写了也是脏数据
    try {
      await history.record(
        id: m.id,
        title: m.title,
        url: m.url,
        sourceKind: m.sourceKind,
        sourceId: m.sourceId,
        poster: m.poster,
        position: _position.inMilliseconds / 1000.0,
        duration: _duration.inMilliseconds / 1000.0,
        episodeIndex: m.episodeIndex,
        seriesId: m.seriesId,
      );
    } catch (e) {
      // 写库失败不能打断播放；这里只留一句人话，不把 url 打出去
      _error = '进度没存上：$e';
      _notify();
    }
  }

  // ── 内核回调 ────────────────────────────────────────────
  void _onPosition(Duration p) {
    _position = p;
    if (p > Duration.zero) _markReady('position>0');
    _notify();
  }

  void _onDuration(Duration d) {
    _duration = d.isNegative ? Duration.zero : d;
    if (_duration > Duration.zero && _position > Duration.zero) {
      _markReady('duration+position');
    }
    _notify();
  }

  /// deferPlayerNotReady：只有「真的有画面/有进度」才算 ready，冷启动慢不算失败
  void _markReady(String why) {
    if (_ready) return;
    final DateTime? t = _openStartedAt ?? _openedAt;
    final int ms = t == null ? -1 : DateTime.now().difference(t).inMilliseconds;
    _ready = true;
    _deferredError = null;
    _deferTimer?.cancel();
    debugPrint('[YQK-DEFER] 播放器 ready（$why），用时 ${ms}ms');
  }

  void _onPlaying(bool v) {
    _playing = v;
    if (v) _markReady('playing=true');
    _notify();
  }

  void _onBuffering(bool v) {
    _buffering = v;
    _notify();
  }

  void _onError(String message) {
    _error = message;
    _notify();
    unawaited(_onPlaybackError(message));
  }

  /// 起播延后判据（原包 deferPlayerNotReady / deferPictureNotVerified /
  /// deferBufferingStabilization）：播放器还没 ready 时报的错先记账，
  /// 等 ready 或等满 10 秒再判，避免冷启动慢就白打接口。
  Future<void> _onPlaybackError(String message) async {
    final bool withinStartup = !_ready;
    if (withinStartup && !_deferTimerFired) {
      _deferredError = message;
      final DateTime? t = _openStartedAt ?? _openedAt;
      final int elapsed = t == null ? 0 : DateTime.now().difference(t).inMilliseconds;
      final int left = deferReadyTimeout.inMilliseconds - elapsed;
      if (left > 0) {
        debugPrint('[YQK-DEFER] 播放器没 ready（${elapsed}ms），先不判失败'
            '（deferPlayerNotReady，最多等 ${deferReadyTimeout.inSeconds}s）');
        _deferTimer?.cancel();
        _deferTimer = Timer(Duration(milliseconds: left), () {
          _deferTimerFired = true;
          final String? pending = _deferredError;
          if (pending == null) return;
          if (_ready) {
            debugPrint('[YQK-DEFER] 已 ready，丢弃这次报错：$pending');
            return;
          }
          debugPrint('[YQK-DEFER] 等满 ${deferReadyTimeout.inSeconds}s 仍未 ready，'
              '按失败处理：$pending');
          unawaited(_retryOnceThenFallback(pending));
        });
        return;
      }
    }
    await _retryOnceThenFallback(message);
  }

  /// 4 号必修：播放报错先原地重试一次（dispose + 用同一个 PlayerMedia 重开），
  /// 第二次还失败才认为直链失效 → invalidate 缓存并让页面去刷新。
  /// 只重试 1 次，不循环；重试期间不清位置。
  Future<void> _retryOnceThenFallback(String message) async {
    final PlayerMedia? media = _media;
    if (media == null) return;
    if (_retrying) {
      debugPrint('[YQK-RETRY] 上一次重试还没结束，忽略这次报错：');
      return;
    }
    _retrying = true;
    try {
      await _retryStage(media, message);
    } finally {
      _retrying = false;
    }
  }

  Future<void> _retryStage(PlayerMedia media, String message) async {
    if (!_replayedOnce) {
      _replayedOnce = true;
      debugPrint('[YQK-REFRESH] local_refresh=false soft_retry=true '
          'backend_refresh=false（先重建播放器，不判定直链失效）');
      final Duration at = _position;
      try {
        // soft_retry：真的重建一次播放器（dispose + 新建同内核 + 用同一地址重开），
        // 不是简单 seek/play —— 解码抖动时前者救得回来，后者救不回来
        final PlaybackKernel old = _kernel;
        await _unbind();
        if (!_kernelInjected) {
          _kernel = KernelFactory.create(_kind);
        }
        _bind();
        unawaited(old.dispose());
        await _kernel.open(
          media.url,
          options: MediaOpenOptions(headers: media.headers),
          start: at,
          play: true,
        );
        debugPrint('[YQK-RETRY] soft_retry 已重建播放器并重开 '
            'at=${at.inMilliseconds}ms');
        _ready = false;
        // soft_retry 之后也要有超时兜底：10 秒还没 ready 就转 backend_refresh，
        // 否则遇到「不报错也不出画」的片子会一直黑着
        _deferTimerFired = false;
        _deferTimer?.cancel();
        _deferTimer = Timer(deferReadyTimeout, () {
          if (_disposed || _ready) return;
          _deferTimerFired = true;
          debugPrint('[YQK-DEFER] soft_retry 后 ${deferReadyTimeout.inSeconds}s '
              '仍没 ready，转 backend_refresh');
          unawaited(_retryStage(media, 'soft_retry 后仍没 ready'));
        });
        return;
      } on Object catch (err) {
        debugPrint('[YQK-RETRY] soft_retry 失败：$err → 转 backend_refresh');
      }
    }
    debugPrint('[YQK-REFRESH] local_refresh=false soft_retry=false '
        'backend_refresh=true（原地重试也失败，交给页面重新解析）');
    debugPrint('[YQK-RETRY] 两次都失败，判定直链失效：$message');
    // 非 mpv 内核还是先试 12 §4.4 的降级（fvp 起不来 → 回 mpv），降不了才交给页面刷新
    final DateTime? opened = _openedAt;
    final bool canFallback = !_kernelInjected &&
        !_triedFallback &&
        _kind != KernelKind.mpv &&
        opened != null &&
        DateTime.now().difference(opened) <= fallbackWindow;
    if (canFallback) {
      await _maybeFallback(message);
      return;
    }
    onFatal?.call(media, message);
  }

  /// 播完 → 自动连播下一集（15 §A3）
  void _onEvent(PlaybackEvent event) {
    if (event.kind != PlaybackEventKind.completed) return;
    unawaited(_autoAdvance());
  }

  Future<void> _autoAdvance() async {
    debugPrint(
        '[YQK-PLAYLIST] 自动连播 autoNext=$autoNext hasNext=$hasNext index=$_playlistIndex/${_playlist.length}');
    if (!autoNext || !hasNext) return;
    _notice('已自动播放下一集');
    await next();
  }

  void _notice(String text) {
    if (_notices.isClosed) return;
    _notices.add(text);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    _persistTimer = null;
    _deferTimer?.cancel();
    _deferTimer = null;
    for (final StreamSubscription<Object?> s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    // 退出播放页写最后一次：交给调用方 await，所以这里只发请求不等待
    unawaited(flushProgress());
    unawaited(_kernel.dispose());
    unawaited(_notices.close());
    super.dispose();
  }
}
