import 'dart:async';

import 'package:flutter/widgets.dart';
// fvp 没有把 FvpPlatform 从公开入口导出，但它确实是官方平台接口里的公开方法；
// 这里要用 createTexture 绕开它内部 _videoSize 的时序坑（见 open() 里的注释）。
// ignore: implementation_imports
import 'package:fvp/src/fvp_platform_interface.dart';
import 'package:fvp/mdk.dart' as mdk;

import '../../domain/media_chapter.dart';
import 'playback_kernel.dart';

/// fvp（MDK）内核：Android 的备用播放内核（15 §A4）。
///
/// 为什么要有它：mpv 在这台机器上只能编译最简 GLSL 核（04 §12.6.2），
/// 而且没有 avfilter（`vf` 不存在）。fvp 走的是另一套解码/渲染栈（MDK），
/// 容器支持面也不同——某些 mpv 播不动的封装（例如带内嵌 ass 的 mkv）它能播。
///
/// 与 mpv 的能力差异（不装、不假装）：
/// - 没有 `aid` / `video-aspect-override` 这类 mpv property，用 MDK 自己的 API
/// - 没有 `sub-delay`（延迟调不动），所以 [supportsSubtitleTuning] = false
/// - 位置没有事件流，用 200ms 轮询；时长读 `mediaInfo.duration`
class FvpKernel implements PlaybackKernel {
  FvpKernel();

  mdk.Player? _player;

  final StreamController<PlaybackEvent> _events =
      StreamController<PlaybackEvent>.broadcast();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playings =
      StreamController<bool>.broadcast();
  final StreamController<bool> _bufferings =
      StreamController<bool>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();

  Timer? _ticker;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  final bool _buffering = false;
  bool _disposed = false;
  bool _completedSent = false;

  /// 音轨/字幕轨缓存（MDK 的 mediaInfo 每次读都会分配内存，别在 build 里读）
  List<AudioTrackInfo> _audio = const <AudioTrackInfo>[];
  List<String> _subs = const <String>[];
  int _audioIndex = 0;

  @override
  @override
  double? get videoAspect {
    // _videoWidth/_videoHeight 来自 MDK 的显示尺寸（含旋转/SAR 处理），默认值是 16×9 占位，没收到真尺寸前返回 null
    if (!_hasVideoSize || _videoWidth <= 0 || _videoHeight <= 0) return null;
    return _videoWidth / _videoHeight;
  }

  @override
  String get name => 'fvp';

  @override
  bool get supportsProperties => false;

  @override
  bool get supportsSubtitleTuning => false;

  /// 最近一次字幕文本回调（验收用；fvp 只给纯文本，不给样式）
  String? _lastSubtitleText;
  int _subCalls = 0;
  String? _lastSubtitleRange;

  /// 验收用：当前内核收到过的最后一条字幕
  String? get lastSubtitleText => _lastSubtitleText;
  String? get lastSubtitleRange => _lastSubtitleRange;

  @override
  Stream<PlaybackEvent> get events => _events.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration> get durationStream => _durations.stream;

  @override
  Stream<bool> get playingStream => _playings.stream;

  @override
  Stream<bool> get bufferingStream => _bufferings.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  bool get playing => _playing;

  @override
  bool get buffering => _buffering;

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) {
    final mdk.Player? p = _player;
    if (p == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int?>(
      valueListenable: p.textureId,
      builder: (BuildContext context, int? id, Widget? _) {
        if (id == null || id < 0) {
          // 纹理还没建好，给一块黑底而不是崩掉
          return const ColoredBox(color: Color(0xFF000000));
        }
        return FittedBox(
          fit: fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _videoWidth,
            height: _videoHeight,
            child: Texture(textureId: id),
          ),
        );
      },
    );
  }

  double _videoWidth = 16;
  double _videoHeight = 9;
  bool _hasVideoSize = false;

  // ── 打开 ────────────────────────────────────────────────
  @override
  Future<void> open(
    String url, {
    MediaOpenOptions options = MediaOpenOptions.none,
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    await _releasePlayer();

    final mdk.Player p = mdk.Player();
    _player = p;
    _completedSent = false;
    _position = start;
    _duration = Duration.zero;

    // MDK 的 setMedia 吃 url / 本地路径 / assets://；请求头它没有对口 API，
    // 带鉴权的网盘交给 mpv 内核（默认内核就是 mpv）。
    p.setMedia(url, mdk.MediaType.video);

    // 第 40 轮定位：prepare 是 fvp 里唯一会 new Completer 的入口，
    // enter/fail 成对出现才能判断 `Bad state: Future already completed`
    // 是不是挂在这一次 await 上（若只有 enter 没有 fail，说明异常走的是
    // 平台通道回调，不在我们的 await 链上）。
    debugPrint('[YQK-OPEN] kernel.prepare enter url=$url');
    final int rc;
    try {
      rc = await p.prepare(position: start.inMilliseconds);
    } on Object catch (err) {
      debugPrint('[YQK-OPEN] kernel.prepare fail url=$url err=$err');
      rethrow;
    }
    debugPrint('[YQK-FVP] prepare($url) -> $rc');
    // fvp 的 prepare 返回值语义（player.dart:425）：0 = 成功，-1 = 已经在加载，
    // -4 = 起始位置越界，-10 = 内部错误。setMedia 之后立刻 prepare 通常就是 -1，
    // 所以 -1 要当成「正在加载」，去等媒体信息而不是当失败。
    if (rc == -4) {
      throw StateError('fvp 起始位置超出范围（prepare=$rc）');
    }
    if (rc < 0 && rc != -1) {
      throw StateError('fvp 打不开这个文件（prepare=$rc）');
    }
    final bool loaded = rc >= 0 || await _waitMediaReady(p);
    if (!loaded) {
      final int dur = p.mediaInfo.duration;
      debugPrint(
          '[YQK-FVP] 等不到媒体信息：duration=$dur state=${p.state}');
      throw StateError('fvp 打不开这个文件（prepare=$rc，等不到媒体信息）');
    }

    // 先起播，纹理才会被真正创建（MDK 的 texture 是随首帧建的，stopped 状态下
    // textureId 一直是 null，直接等尺寸会白等 8 秒然后黑屏）。
    p.playbackRate = _rate;
    p.volume = _volume;
    p.state = play ? mdk.PlaybackState.playing : mdk.PlaybackState.paused;
    _playing = play;

    // 等纹理就绪，再按视频真实尺寸建纹理；拿不到就退 16:9，别让整页黑着
    await _waitTexture(p);
    final mdk.MediaInfo info = p.mediaInfo;
    final List<mdk.VideoStreamInfo> vids =
        info.video ?? <mdk.VideoStreamInfo>[];
    final List<mdk.SubtitleStreamInfo> subs =
        info.subtitle ?? <mdk.SubtitleStreamInfo>[];
    debugPrint('[YQK-FVP] media dur=${info.duration} '
        'video=${vids.length} audio=${(info.audio ?? <mdk.AudioStreamInfo>[]).length} '
        'subs=${subs.length} '
        'firstVideoCodec=${vids.isEmpty ? '-' : vids.first.codec.codec} '
        '${vids.isEmpty ? '' : '${vids.first.codec.width}x${vids.first.codec.height}'}');
    for (final mdk.SubtitleStreamInfo s in subs) {
      debugPrint('[YQK-FVP] sub track index=${s.index} '
          'codec=${s.codec.codec} title=${s.metadata['title'] ?? '-'} '
          'lang=${s.metadata['language'] ?? '-'}');
    }
    // 字幕文本回调（fvp 只给纯文本，不给 bitmap/样式）
    p.onSubtitleText((double start, double end, List<String> text) {
      _subCalls++;
      debugPrint('[YQK-FVP-SUB] #$_subCalls start=${start.toStringAsFixed(2)} '
          'end=${end.toStringAsFixed(2)} text=${text.join(r'\N')}');
      _lastSubtitleText = text.join('\n');
      _lastSubtitleRange = '${start.toStringAsFixed(1)}-${end.toStringAsFixed(1)}';
    });
    debugPrint('[YQK-FVP] onSubtitleText 已挂');
    // 纹理：mdk 的 updateTexture 依赖内部的 _videoSize，而它只在「状态切换到
    // loaded」那一刻才被赋值；我们用 setMedia+prepare 的路径常常错过那一次，
    // 结果 updateTexture 永远返回 -1、textureId 一直是 null（画面纯黑）。
    // 这里直接按解出来的视频尺寸建纹理，绕开那个时序依赖。
    final int texId = await _createTexture(p, vids);
    if (texId >= 0) {
      p.textureId.value = texId;
    } else {
      await p.updateTexture(
          width: _videoWidth.round(), height: _videoHeight.round());
    }
    debugPrint('[YQK-FVP] loaded dur=${p.mediaInfo.duration} '
        'state=${p.state} tex=${p.textureId.value} '
        'size=${_videoWidth.toInt()}x${_videoHeight.toInt()}');
    unawaited(_probeSubtitleWarm(p, subs));

    _refreshTracks();
    _emit(const PlaybackEvent(PlaybackEventKind.opened));

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (Timer _) {
      _tick();
    });
  }

  /// 内嵌字幕热态探测（2026-11-06 重测方案）。
  ///
  /// 之前的 2 秒切片探测跑在「纹理还没出来」的阶段（本机首帧 6.38s），
  /// 那时解码器没工作，字幕回调当然不来，于是误判成「内嵌轨不可信」。
  /// 现在改成：等纹理 ready → seek 0 → 全程播放 20 秒累积回调，
  /// 中途不动候选值；若 20 秒仍 0 次，再落点 5.5s（第 2 条字幕里）试 3 秒。
  Future<void> _probeSubtitleWarm(
    mdk.Player p,
    List<mdk.SubtitleStreamInfo> subs,
  ) async {
    if (subs.isEmpty) {
      debugPrint('[YQK-FVP] 没有字幕轨，跳过内嵌字幕探测');
      return;
    }
    final mdk.SubtitleStreamInfo track = subs.last;
    final String codec = track.codec.codec;
    p.setActiveTracks(mdk.MediaType.subtitle, <int>[track.index]);
    debugPrint('[YQK-FVP] 内嵌字幕轨固定 [${track.index}] codec=$codec，'
        '等纹理 ready 后开始 20 秒探测');
    await p.seek(position: 0);
    p.state = mdk.PlaybackState.playing;
    final int before = _subCalls;
    await Future<void>.delayed(const Duration(seconds: 20));
    final int first = _subCalls - before;
    debugPrint('[YQK-FVP] 内嵌字幕 20 秒内回调 $first 次，track=$codec');
    if (first > 0) return;

    // 第二招：落点 5.5s（字幕区间 5.0–9.5s 内），固定同一个轨播 3 秒
    await p.seek(position: 5500);
    p.state = mdk.PlaybackState.playing;
    final int before2 = _subCalls;
    await Future<void>.delayed(const Duration(seconds: 3));
    debugPrint('[YQK-FVP] 内嵌字幕落点 5.5s 后 3 秒内回调 '
        '${_subCalls - before2} 次，track=$codec');
  }

  /// 按视频流真实尺寸建一块 Flutter 纹理；拿不到尺寸就退 16:9。
  Future<int> _createTexture(
      mdk.Player p, List<mdk.VideoStreamInfo> vids) async {
    int w = 1920;
    int h = 1080;
    if (vids.isNotEmpty) {
      final mdk.VideoCodecParameters c = vids.first.codec;
      if (c.width > 0 && c.height > 0) {
        w = c.width;
        h = (c.height / (c.par == 0 ? 1 : c.par)).round();
        if (vids.first.rotation % 180 == 90) {
          final int t = w;
          w = h;
          h = t;
        }
      }
    }
    _videoWidth = w.toDouble();
    _videoHeight = h.toDouble();
    _hasVideoSize = true;
    try {
      return await FvpPlatform.instance
          .createTexture(p.nativeHandle, w, h, false);
    } on Object catch (e) {
      debugPrint('[YQK-FVP] createTexture 失败：$e');
      return -1;
    }
  }

  /// 等 MDK 建好 texture（起播后异步建，通常 1 帧内就有）。
  Future<void> _waitTexture(mdk.Player p,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) return;
      final int? id = p.textureId.value;
      if (id != null && id >= 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('[YQK-FVP] 等不到纹理（state=${p.state}）');
  }

  /// 等 MDK 真正把媒体信息解出来（prepare 返回 -1 时用）。
  ///
  /// 判据：能拿到时长，或者状态已经不是 notRunning 且已经解出视频尺寸。
  Future<bool> _waitMediaReady(mdk.Player p,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) return false;
      final mdk.MediaInfo info = p.mediaInfo;
      if (info.duration > 0) return true;
      final bool hasVideo = (info.video ?? <mdk.VideoStreamInfo>[]).isNotEmpty;
      if (hasVideo && p.state != mdk.PlaybackState.notRunning) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  void _tick() {
    final mdk.Player? p = _player;
    if (p == null || _disposed) return;

    final Duration pos = Duration(milliseconds: p.position);
    if (pos != _position) {
      _position = pos;
      if (!_positions.isClosed) _positions.add(pos);
      _emit(PlaybackEvent(PlaybackEventKind.position, position: pos));
    }

    final Duration dur = Duration(milliseconds: p.mediaInfo.duration);
    if (dur > Duration.zero && dur != _duration) {
      _duration = dur;
      if (!_durations.isClosed) _durations.add(dur);
      _emit(PlaybackEvent(PlaybackEventKind.duration, duration: dur));
    }

    final bool playingNow = p.state == mdk.PlaybackState.playing;
    if (playingNow != _playing) {
      _playing = playingNow;
      if (!_playings.isClosed) _playings.add(_playing);
      _emit(PlaybackEvent(PlaybackEventKind.playing, playing: _playing));
    }

    // 播完：位置贴到片尾 300ms 内，只报一次
    if (!_completedSent &&
        _duration > const Duration(seconds: 1) &&
        _position >= _duration - const Duration(milliseconds: 300)) {
      _completedSent = true;
      _emit(const PlaybackEvent(PlaybackEventKind.completed));
    }
  }

  void _refreshTracks() {
    final mdk.Player? p = _player;
    if (p == null) return;
    final mdk.MediaInfo info = p.mediaInfo;
    _audio = <AudioTrackInfo>[
      for (final mdk.AudioStreamInfo a in info.audio ?? <mdk.AudioStreamInfo>[])
        AudioTrackInfo(
          index: a.index,
          label: _audioLabel(a),
          language: a.metadata['language'],
          channels: a.codec.channels,
        ),
    ];
    _subs = <String>[
      for (final mdk.SubtitleStreamInfo s
          in info.subtitle ?? <mdk.SubtitleStreamInfo>[])
        _subLabel(s),
    ];
    final List<int> active = p.activeAudioTracks;
    _audioIndex = active.isEmpty
        ? 0
        : _audio.indexWhere((AudioTrackInfo t) => t.index == active.first);
    if (_audioIndex < 0) _audioIndex = 0;
  }

  String _audioLabel(mdk.AudioStreamInfo a) {
    final List<String> parts = <String>[];
    final String? lang = a.metadata['language'];
    if (lang != null && lang.isNotEmpty && lang != 'und') parts.add(lang);
    if (a.codec.codec.isNotEmpty) parts.add(a.codec.codec.toUpperCase());
    if (a.codec.channels > 0) parts.add('${a.codec.channels} 声道');
    if (parts.isEmpty) parts.add('音轨 ${a.index + 1}');
    return parts.join(' · ');
  }

  String _subLabel(mdk.SubtitleStreamInfo s) {
    final String? lang = s.metadata['language'];
    final String codec = s.codec.codec.toUpperCase();
    final List<String> parts = <String>[];
    if (lang != null && lang.isNotEmpty && lang != 'und') parts.add(lang);
    if (codec.isNotEmpty) parts.add(codec);
    if (parts.isEmpty) parts.add('字幕 ${s.index + 1}');
    return parts.join(' · ');
  }

  // ── 播放控制 ────────────────────────────────────────────
  @override
  Future<void> play() async {
    _player?.state = mdk.PlaybackState.playing;
  }

  @override
  Future<void> pause() async {
    _player?.state = mdk.PlaybackState.paused;
  }

  @override
  Future<void> seek(Duration d) async {
    final mdk.Player? p = _player;
    if (p == null) return;
    await p.seek(position: d.inMilliseconds);
    _position = d;
    _completedSent = false;
    if (!_positions.isClosed) _positions.add(d);
    _emit(PlaybackEvent(PlaybackEventKind.position, position: d));
  }

  double _rate = 1.0;
  double _volume = 1.0;

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    _player?.playbackRate = rate;
  }

  @override
  Future<void> setVolume(double v) async {
    // PlaybackKernel 的口径是 0–100（和 mpv volume 一致），MDK 是 0–1
    _volume = (v / 100).clamp(0, 1.3).toDouble();
    _player?.volume = _volume;
  }

  // ── 字幕 ────────────────────────────────────────────────
  @override
  Future<void> setSubtitle(String? pathOrUri, {String? title}) async {
    final mdk.Player? p = _player;
    if (p == null) return;
    if (pathOrUri == null || pathOrUri.isEmpty) {
      p.setActiveTracks(mdk.MediaType.subtitle, <int>[]);
      return;
    }
    p.setMedia(pathOrUri, mdk.MediaType.subtitle);
    // 外挂字幕挂上后，mdk 会把它作为一条新的 subtitle track 加进 mediaInfo；
    // 用真实 track index 激活（-1 在部分版本上不生效）
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final List<mdk.SubtitleStreamInfo> all = p.mediaInfo.subtitle ?? const <mdk.SubtitleStreamInfo>[];
    final int idx = all.isEmpty ? -1 : all.last.index;
    p.setActiveTracks(mdk.MediaType.subtitle, <int>[idx]);
    p.state = mdk.PlaybackState.paused;
    p.state = mdk.PlaybackState.playing;
    debugPrint('[YQK-FVP] 外挂字幕已挂：$pathOrUri tracks=${all.length} active=$idx');
  }

  @override
  Future<void> setSubDelay(double seconds) async {
    // MDK 没有 sub-delay；调用方靠 supportsSubtitleTuning 不给这个入口
  }

  @override
  Future<void> setSubFontSize(double size) async {
    // MDK 字幕由 libass 渲染，字号走 property（支持就生效，不支持就静默忽略）
    await setProperty('sub-font-size', size.round().toString());
  }

  @override
  List<String> get subtitleTrackNames => _subs;

  @override
  Future<void> setSubtitleTrack(int index) async {
    final mdk.Player? p = _player;
    if (p == null) return;
    if (index < 0 || index >= _subs.length) {
      p.setActiveTracks(mdk.MediaType.subtitle, <int>[]);
      return;
    }
    p.setActiveTracks(mdk.MediaType.subtitle, <int>[_audioOrSubIndex(_subs, index)]);
  }

  int _audioOrSubIndex(List<String> labels, int i) {
    final mdk.Player? p = _player;
    final List<mdk.SubtitleStreamInfo> subs =
        p?.mediaInfo.subtitle ?? <mdk.SubtitleStreamInfo>[];
    if (i < subs.length) return subs[i].index;
    return i;
  }

  // ── 音轨 ────────────────────────────────────────────────
  @override
  List<String> get audioTrackNames =>
      <String>[for (final AudioTrackInfo t in _audio) t.label];

  @override
  List<AudioTrackInfo> get audioTracks => _audio;

  @override
  int get currentAudioTrack => _audioIndex;

  @override
  Future<void> setAudioTrack(int index) async {
    final mdk.Player? p = _player;
    if (p == null || index < 0 || index >= _audio.length) return;
    p.setActiveTracks(mdk.MediaType.audio, <int>[_audio[index].index]);
    _audioIndex = index;
  }

  @override
  Future<void> selectLastAudioTrack() async {
    final mdk.Player? p = _player;
    if (p == null || _audio.isEmpty) return;
    await setAudioTrack(_audio.length - 1);
  }
  @override
  Future<void> addExternalAudio(String path) async {
    // MDK 没有给播放中的媒体追加外部音轨的接口（只有 setActiveTracks 选内嵌轨），
    // 所以外挂音轨只对 mpv 内核提供；这里显式抛，UI 会提示切回 mpv。
    throw UnsupportedError('外挂音轨只有 mpv 内核支持，切回 mpv 再挂');
  }

  // ── 画面 / 属性 ─────────────────────────────────────────
  @override
  Future<void> setAspectRatio(double ratio) async {
    _player?.setAspectRatio(ratio <= 0 ? -1 : ratio);
  }

  @override
  Future<void> setShaderChain(List<String> absolutePaths) async {
    // MDK 没有 GLSL 用户 shader 接口（04 §12.6.2），这里天然是空实现
  }

  @override
  Future<void> setProperty(String key, String value) async {
    _player?.setProperty(key, value);
  }

  /// H4：fvp（MDK）没有章节 API —— MediaInfo 里只有 video/audio/subtitle 三条流，
  /// 章节信息在这个内核里取不到，所以恒返回空表（如实，不假装支持）。
  @override
  Future<List<MediaChapter>> chapters() async => const <MediaChapter>[];

  @override
  Future<String?> readProperty(String key) async {
    final mdk.Player? p = _player;
    if (p == null) return null;
    // MDK 的 getProperty 不一定有，按已知项自己拼
    switch (key) {
      case 'video-codec-name':
        final List<mdk.VideoStreamInfo> v =
            p.mediaInfo.video ?? <mdk.VideoStreamInfo>[];
        return v.isEmpty ? null : v.first.codec.codec;
      case 'audio-codec-name':
        final List<mdk.AudioStreamInfo> a =
            p.mediaInfo.audio ?? <mdk.AudioStreamInfo>[];
        return a.isEmpty ? null : a.first.codec.codec;
      default:
        return null;
    }
  }

  @override
  Future<Map<String, String?>> debugProperties(List<String> keys) async {
    final mdk.Player? p = _player;
    final Map<String, String?> out = <String, String?>{};
    for (final String k in keys) {
      switch (k) {
        case 'video-params':
          final List<mdk.VideoStreamInfo> v =
              p?.mediaInfo.video ?? <mdk.VideoStreamInfo>[];
          out[k] = v.isEmpty
              ? null
              : '${v.first.codec.width}x${v.first.codec.height} '
                  '${v.first.codec.codec}';
        case 'demuxer-cache-duration':
          out[k] = p == null ? null : '${p.buffered()}ms';
        case 'frame-drop-count':
          out[k] = '0'; // MDK 不暴露丢帧计数
        default:
          out[k] = await readProperty(k);
      }
    }
    return out;
  }

  // ── 生命周期 ────────────────────────────────────────────
  void _emit(PlaybackEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> _releasePlayer() async {
    _ticker?.cancel();
    _ticker = null;
    final mdk.Player? p = _player;
    _player = null;
    if (p != null) {
      try {
        p.dispose();
      } on Object catch (err) {
        debugPrint('[YQK-FVP] dispose 失败：$err');
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _releasePlayer();
    await _events.close();
    await _positions.close();
    await _durations.close();
    await _playings.close();
    await _bufferings.close();
    await _errors.close();
  }
}
