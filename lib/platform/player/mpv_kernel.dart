import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../domain/media_chapter.dart';
import 'playback_kernel.dart';

/// mpv 内核：对应原包里的 libmpv.so（04 §12 / 15 §A1）。
///
/// 参数表来自 04 §12.3 + 15 §A1，一个都没改。**这里不设 vo**：
/// media_kit_video 2.0.1 的 Android 后端默认就是 `vo=gpu`
/// （android_video_controller/real.dart:151 `vo: configuration.vo ?? 'gpu'`），
/// 而 gpu-next 字符串在这套 libmpv 里 0 处（`-Dlibplacebo=disabled -Dvulkan=disabled`
/// 编的，见 04 §12.6），写进去只会 `video output 'gpu-next' not found` 然后黑屏。
/// Anime4K 走 `vo=gpu` + `glsl-shaders`，不需要 gpu-next。
class MpvKernel implements PlaybackKernel {
  MpvKernel({this.softwareDecode = false}) {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: kAppName,
        // 64MB 是 15 §A1 的甜点值；常量在 03 §11 的 kDefaultBufferMb
        bufferSize: kDefaultBufferMb * 1024 * 1024,
        logLevel: MPVLogLevel.error,
        // 故意不传 vo：保持 media_kit 的默认 'gpu'（04 §12.6 事实二）
        vo: null,
      ),
    );
    _video = VideoController(_player);
    // 参数统一在 open() 里落：media_kit 的 NativePlayer 初始化是异步的，
    // setProperty 内部会 await waitForPlayerInitialization，所以第一次写会等
    // 初始化完成（约 1s），不能给它 300ms 的短超时，否则整张参数表都白写。
    unawaited(_applyBaseProperties());

    _player.stream.position.listen((Duration p) {
      _position = p;
      _events.add(PlaybackEvent(PlaybackEventKind.position, position: p));
    });
    _player.stream.duration.listen((Duration d) {
      _duration = d;
      _events.add(PlaybackEvent(PlaybackEventKind.duration, duration: d));
    });
    _player.stream.completed.listen((bool done) {
      if (done) _events.add(const PlaybackEvent(PlaybackEventKind.completed));
    });
    _player.stream.error.listen((String e) {
      _error.add(e);
      _events.add(PlaybackEvent(PlaybackEventKind.error, message: e));
    });
    // 只在 debug 构建里把 mpv 日志打到 logcat：排查 vo/shader 用，
    // release 包不会打印（06 §2 MUST NOT 第 10 条的精神：别把日志泄漏到正式包）
    if (kDebugMode) {
      _player.stream.log.listen((dynamic l) {
        debugPrint('[YQK-MPV] ${l.prefix}: ${l.text}');
      });
    }
  }

  /// 个别设备硬解会绿屏/黑屏（15 §A1 坑），可切软解兜底
  final bool softwareDecode;

  late final Player _player;
  late final VideoController _video;

  final StreamController<PlaybackEvent> _events =
      StreamController<PlaybackEvent>.broadcast();
  final StreamController<String> _error = StreamController<String>.broadcast();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _headerFieldsApplied = false;
  bool _proxyApplied = false;

  @override
  String get name => 'mpv';

  @override
  Stream<PlaybackEvent> get events => _events.stream;

  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;
  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration.isNegative ? Duration.zero : _duration;
  @override
  @override
  double? get videoAspect {
    // dw/dh 是「按正确宽高比缩放后」的显示尺寸（已含 SAR），w/h 是编码尺寸，别用后者
    final vp = _player.state.videoParams;
    final int? dw = vp.dw;
    final int? dh = vp.dh;
    if (dw == null || dh == null || dw <= 0 || dh <= 0) return null;
    return dw / dh;
  }

  @override
  bool get playing => _player.state.playing;
  @override
  bool get buffering => _player.state.buffering;

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) =>
      Video(controller: _video, fit: fit, controls: NoVideoControls);

  // ── 音轨 / 字幕轨 ───────────────────────────────────────
  @override
  List<String> get audioTrackNames {
    final List<AudioTrack> tracks = _player.state.tracks.audio;
    return <String>[
      for (int i = 0; i < tracks.length; i++) tracks[i].title ?? '音轨 ${i + 1}',
    ];
  }

  @override
  List<AudioTrackInfo> get audioTracks {
    // media_kit 的 state.tracks.audio 里混着 auto / no 两个伪轨（id 是字符串
    // 'auto' 和 'no'），它们不是真音轨，界面上不能列出来（会给点了没反应的项）。
    final List<AudioTrack> all = _player.state.tracks.audio;
    final List<AudioTrack> real = all
        .where((AudioTrack t) => int.tryParse(t.id) != null)
        .toList(growable: false);
    // state 还没刷新到真轨时（只剩 auto/no）就退回原始列表，别给空列表
    final List<AudioTrack> tracks = real.isEmpty ? all : real;
    return <AudioTrackInfo>[
      for (int i = 0; i < tracks.length; i++)
        AudioTrackInfo(
          index: i,
          label: _audioLabel(tracks[i], i),
          language: tracks[i].language,
          channels: tracks[i].channelscount,
        ),
    ];
  }

  /// 「日语 · AAC · 2 声道」这种给人看的标签（05 §3.2）
  String _audioLabel(AudioTrack track, int i) {
    final List<String> parts = <String>[];
    final String? lang = track.language;
    if (lang != null && lang.isNotEmpty && lang != 'und') {
      parts.add(_languageName(lang));
    }
    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!.toUpperCase());
    }
    final int? ch = track.channelscount;
    if (ch != null && ch > 0) parts.add('$ch 声道');
    if (parts.isEmpty) parts.add('音轨 ${i + 1}');
    return parts.join(' · ');
  }

  /// ISO 639 → 中文名，认不出就原样显示
  static String _languageName(String code) {
    switch (code.toLowerCase()) {
      case 'zh':
      case 'chi':
      case 'zho':
        return '中文';
      case 'en':
      case 'eng':
        return '英语';
      case 'ja':
      case 'jpn':
        return '日语';
      case 'ko':
      case 'kor':
        return '韩语';
      case 'fr':
      case 'fre':
        return '法语';
      case 'de':
      case 'ger':
        return '德语';
      default:
        return code;
    }
  }

  @override
  bool get supportsSubtitleTuning => true;

  @override
  Future<void> setAspectRatio(double ratio) async {
    // <=0 = 原始比例：mpv 的口径是 -1
    await setProperty('video-aspect-override', ratio <= 0 ? '-1' : '$ratio');
  }

  @override
  Future<Map<String, String?>> debugProperties(List<String> keys) async {
    final Map<String, String?> out = <String, String?>{};
    for (final String k in keys) {
      out[k] = await readProperty(k);
    }
    return out;
  }

  @override
  Future<void> addExternalAudio(String path) async {
    // 15 §A6 / 13 §A6′：audio-file 挂上去之后 mpv 会多出一条音轨，
    // 之后由用户在本页音轨弹层里选中它（aid）。路径必须是可读的绝对路径。
    // mpv 的运行时指令是 audio-add（audio-file 只是打开前的选项，set_property 不生效）
    final dynamic platform = _player.platform;
    if (platform is NativePlayer) {
      // 不带 select：让 aid 先保持在原音轨上，随后由 selectLastAudioTrack 显式切
      await platform.command(<String>['audio-add', path]);
    } else {
      await setProperty('audio-file', path);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final String? af = await readProperty('audio-file');
    final String? aid = await readProperty('aid');
    debugPrint('[YQK-AUDIOFILE] 已挂外挂音轨：$path audio-file=$af aid=$aid');
  }

  @override
  int get currentAudioTrack {
    final List<AudioTrack> tracks = _player.state.tracks.audio;
    final String id = _player.state.track.audio.id;
    final int i = tracks.indexWhere((AudioTrack t) => t.id == id);
    return i < 0 ? 0 : i;
  }

  @override
  Future<void> setAudioTrack(int index) async {
    final List<AudioTrack> tracks = _player.state.tracks.audio;
    if (index < 0 || index >= tracks.length) return;
    await _safeSetProperty('aid', tracks[index].id);
  }

  @override
  Future<void> selectLastAudioTrack() async {
    final List<AudioTrack> tracks = _player.state.tracks.audio;
    if (tracks.isEmpty) return;
    // mpv 的 track id 就是 aid，取数值最大的那条 = 最后挂上去的那条
    AudioTrack best = tracks.first;
    int bestId = int.tryParse(best.id) ?? 0;
    for (final AudioTrack t in tracks) {
      final int id = int.tryParse(t.id) ?? 0;
      if (id > bestId) {
        best = t;
        bestId = id;
      }
    }
    // 15 A6：直接写 aid 最稳（media_kit 的 setAudioTrack 依赖 state，外挂轨常常拿不到）
    debugPrint('[YQK-AID] track ids=${tracks.map((AudioTrack t) => t.id).join(',')} '
        'best=${best.id}');
    await setProperty('aid', best.id);
  }

  @override
  List<String> get subtitleTrackNames {
    final List<SubtitleTrack> tracks = _player.state.tracks.subtitle;
    return <String>[
      for (int i = 0; i < tracks.length; i++)
        tracks[i].title ?? '字幕 ${i + 1}',
    ];
  }

  @override
  Future<void> setSubtitleTrack(int index) async {
    final List<SubtitleTrack> tracks = _player.state.tracks.subtitle;
    if (index < 0 || index >= tracks.length) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    await _player.setSubtitleTrack(tracks[index]);
  }

  // ── 打开 ────────────────────────────────────────────────
  @override
  Future<void> open(
    String url, {
    MediaOpenOptions options = MediaOpenOptions.none,
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    // 请求头：http-header-fields 能覆盖 media_kit 没转发的头（Cookie/自定义头），
    // Media(httpHeaders:) 则保证 mpv 的 HTTP 层拿到同一份。
    final Map<String, String> headers = options.headers;
    if (headers.isNotEmpty) {
      final String fields = headers.entries
          .where((MapEntry<String, String> e) => e.key.trim().isNotEmpty)
          .map(
            (MapEntry<String, String> e) =>
                '${_cleanHeader(e.key)}: '
                '${_cleanHeader(e.value).replaceAll(',', r'\,')}',
          )
          .join(',');
      await _safeSetProperty('http-header-fields', fields);
      _headerFieldsApplied = fields.isNotEmpty;
    } else if (_headerFieldsApplied) {
      // 上一次播放带的头不能残留到下一个地址
      await _safeSetProperty('http-header-fields', '');
      _headerFieldsApplied = false;
    }

    // 空串代理地址会被 mpv 当成非法值，导致 open 一直等不到就绪
    final String proxy = options.httpProxy?.trim() ?? '';
    if (proxy.isNotEmpty) {
      await _safeSetProperty('http-proxy', proxy);
      _proxyApplied = true;
    } else if (_proxyApplied) {
      await _safeSetProperty('http-proxy', '');
      _proxyApplied = false;
    }
    await _safeSetProperty(
      'tls-verify',
      options.tlsVerify == false ? 'no' : 'yes',
    );
    for (final MapEntry<String, String> e in options.properties.entries) {
      if (e.value.trim().isEmpty) continue;
      await _safeSetProperty(e.key, e.value);
    }

    // Android 上 libmpv 用 mbedtls，**默认没有 CA store**：任何 https 都会在
    // 握手阶段报 `tls: mbedtls_ssl_handshake returned -0x2700`（证书校验失败）。
    // 把系统 CA 目录拼成 PEM bundle 交给 mpv，比关掉校验（tls-verify=no）安全。
    final String? caFile = await ensureCaBundle();
    if (caFile != null) {
      await _safeSetProperty('tls-ca-file', caFile);
    }


    final Media media = Media(url, httpHeaders: headers);
    // 续播要在媒体真的加载完再 seek：open() 只是把地址交给 mpv 就返回了，
    // 这时 seek 会被丢掉（画面从 0 开始，看起来像"续播没生效"）。
    // 所以带起点时先不播，等 duration 出来（= 已加载），seek 到位再开播。
    final bool resume = start > Duration.zero;
    // 打不开就尽快失败，交给播放页的「打不开」文案，而不是无限转圈
    await _player.open(media, play: resume ? false : play).timeout(
      kHttpReadTimeout,
      onTimeout: () => throw StateError('mpv 打开超时：${_redact(url)}'),
    );
    // open 之后 mpv 才真的就绪，这时写属性才有响应（见构造函数注释）
    await _applyBaseProperties();
    if (resume) {
      try {
        await _player.stream.duration
            .firstWhere((Duration d) => d > Duration.zero)
            .timeout(kHttpReadTimeout);
      } on Object {
        // 加载超时：照样往下走，从头开始总比黑屏好
      }
      await _player.seek(start);
      if (play) await _player.play();
    }
    if (softwareDecode) {
      await _safeSetProperty('hwdec', 'no');
    }
    _opened = true;
    // shader 链要等**第一帧真正出来**再挂：太早设置会让 vo 在 surface 还没
    // 交给 mpv 时重建，Android 上表现为黑屏（画面不出来，声音正常）。
    if (_shaderChain.isNotEmpty) {
      try {
        await _player.stream.position
            .firstWhere((Duration p) => p > Duration.zero)
            .timeout(kServerBootTimeout);
      } on Object {
        // 没等到也挂上，能出画面就行
      }
      await _safeSetProperty('glsl-shaders', _chainValue);
    }
    _startDropWatch();
    _events.add(const PlaybackEvent(PlaybackEventKind.opened));
  }

  static String? _cachedCaBundle;

  /// 把系统 CA（/system/etc/security/cacerts/*.0，都是 PEM）拼成一个 bundle，
  /// 交给 mpv 的 `tls-ca-file`。只拼一次，之后复用应用目录里的缓存文件。
  ///
  /// 为什么需要：Android 版 libmpv 走 mbedtls，不带系统信任链，https 会卡在
  /// `-0x2700`（证书校验失败）。这里补信任链，而不是把校验关掉。
  static Future<String?> ensureCaBundle() async {
    if (_cachedCaBundle != null) return _cachedCaBundle;
    try {
      final Directory support = await getApplicationSupportDirectory();
      final File bundle = File(p.join(support.path, 'certs', 'ca-bundle.pem'));
      if (await bundle.exists() && await bundle.length() > 0) {
        _cachedCaBundle = bundle.path;
        return _cachedCaBundle;
      }

      final Directory system = Directory('/system/etc/security/cacerts');
      if (!await system.exists()) return null;

      final StringBuffer sb = StringBuffer();
      final List<File> certs = <File>[];
      await for (final FileSystemEntity e in system.list()) {
        if (e is File && e.path.endsWith('.0')) certs.add(e);
      }
      certs.sort((File a, File b) => a.path.compareTo(b.path));
      for (final File f in certs) {
        try {
          sb.writeln((await f.readAsString()).trim());
        } catch (_) {
          // 单个证书读不出来就跳过，不影响其它
        }
      }
      if (sb.isEmpty) return null;

      await bundle.parent.create(recursive: true);
      await bundle.writeAsString(sb.toString(), flush: true);
      _cachedCaBundle = bundle.path;
      return _cachedCaBundle;
    } catch (_) {
      return null;
    }
  }

  /// 04 §12.3 + 15 §A1 的 18 个参数（vo 除外，原因见构造函数注释）
  static const Map<String, String> _baseProperties = <String, String>{
    'hwdec': 'auto', // 15 §A1：auto 失败会自动回落软解
    'cache': 'yes',
    'demuxer-max-bytes': '64MiB',
    'demuxer-readahead-secs': '30',
    'network-timeout': '15', // 秒
    'video-sync': 'audio', // 同步到音频，避免画面撕裂
    'interpolation': 'no', // 插帧会跟 shader 抢 GPU
    'scale': 'bilinear', // shader 接管上采样，mpv 用最便宜的
    'dither-depth': 'auto',
    'sub-auto': 'fuzzy', // 自动加载同名字幕
    'sub-font-size': '42',
    'sub-border-size': '2.0',
    'sub-color': '#FFFFFF',
    'osd-level': '0',
    // 这套 libmpv 把字幕画在旋转 90 度的右边缘（截图 s5/s6/s7.png 右下竖排残影），
    // 字幕改由 Flutter 层自绘（subtitle_overlay.dart），mpv 字幕层关掉
    'sub-visibility': 'no',
    'really-quiet': 'yes',
    'audio-pitch-correction': 'yes', // 15 §A8：变速不变调
    'audio-passthrough': 'no', // 15 §A6：auto 在没功放时会没声音
    'audio-normalize-downmix': 'yes',
  };

  Future<void> _applyBaseProperties() async {
    for (final MapEntry<String, String> e in _baseProperties.entries) {
      await _safeSetProperty(e.key, e.value);
    }
  }

  @override
  Future<String?> readProperty(String key) async {
    try {
      // media_kit 的 NativePlayer 有 getProperty，PlatformPlayer 接口没暴露，
      // 只能 dynamic 取；读不到就返回 null，不影响播放。
      final dynamic platform = _player.platform;
      final dynamic r = await platform.getProperty(key, waitForInitialization: false);
      return r?.toString();
    } catch (_) {
      return null;
    }
  }

  /// H4：读 mpv 的 `chapter-list`（属性名带连字符，不是 chapterList）。
  ///
  /// 每项形状 `{title: String, time: double}`，**没有 end**：
  /// end 用下一条的 start，最后一条用当前 duration（拿不到就 -1 = 到片尾）。
  /// 全程只读，绝不写回片源文件。
  @override
  Future<List<MediaChapter>> chapters() async {
    try {
      final dynamic platform = _player.platform;
      // 直接拿原始节点：readProperty 会 toString()，List<Map> 就废了
      final dynamic raw = await platform.getProperty('chapter-list',
          waitForInitialization: false);
      final List<double> starts = <double>[];
      final List<String> titles = <String>[];
      if (raw is List) {
        // 有的 media_kit 版本直接给 List<Map>
        for (final dynamic item in raw) {
          if (item is! Map) continue;
          final dynamic t = item['time'];
          final double start =
              t is num ? t.toDouble() : double.tryParse('$t') ?? -1;
          if (start < 0) continue;
          starts.add(start);
          titles.add('${item['title'] ?? ''}');
        }
      } else {
        // 实测走到这里：raw 是 JSON 字符串，
        // 形如 [{"title":"OP","time":0.000000},{"title":"Main","time":92.523000}]
        final String s = '$raw';
        debugPrint('[YQK-CHAPX] rawstr=${s.length > 220 ? s.substring(0, 220) : s}');
        List<dynamic> arr = const <dynamic>[];
        try {
          final dynamic d = jsonDecode(s);
          if (d is List) arr = d;
        } on Object catch (_) {}
        if (arr.isNotEmpty) {
          for (final dynamic item in arr) {
            if (item is! Map) continue;
            final dynamic t = item['time'];
            final double start =
                t is num ? t.toDouble() : double.tryParse('$t') ?? -1;
            if (start < 0) continue;
            starts.add(start);
            titles.add('${item['title'] ?? ''}');
          }
        } else {
          // 兜底：mpv 文本形态 [{title=OP, time=0.000000}, ...]
          for (final RegExpMatch m
              in RegExp(r'time\s*[=:]\s*(-?[0-9]+(?:\.[0-9]+)?)').allMatches(s)) {
            final double start = double.tryParse(m.group(1)!) ?? -1;
            if (start < 0) continue;
            starts.add(start);
          }
          for (final RegExpMatch m
              in RegExp(r'title\s*[=:]\s*"?([^,}"]*)').allMatches(s)) {
            titles.add(m.group(1)!.trim());
          }
        }
        while (titles.length < starts.length) {
          titles.add('');
        }
      }
      debugPrint('[YQK-CHAPX] raw=${raw.runtimeType} starts=${starts.length}');
      if (starts.isEmpty) return const <MediaChapter>[];
      // mpv 一般已按时间升序；这里再稳一次，乱序也不会算错 end
      final List<int> order = List<int>.generate(starts.length, (int i) => i)
        ..sort((int a, int b) => starts[a].compareTo(starts[b]));
      final double total = _duration.inMilliseconds / 1000.0;
      final List<MediaChapter> out = <MediaChapter>[];
      for (int k = 0; k < order.length; k++) {
        final int i = order[k];
        final double end = k + 1 < order.length
            ? starts[order[k + 1]]
            : (total > 0 ? total : -1);
        out.add(MediaChapter(start: starts[i], end: end, title: titles[i]));
      }
      return out;
    } catch (e) {
      debugPrint('[YQK-CHAP] chapter-list 读取失败：$e');
      return const <MediaChapter>[];
    }
  }

  Timer? _dropTimer;

  /// 验收用：每 5 秒把 mpv 的掉帧计数打进 logcat（只有 debug 构建会打）
  void _startDropWatch() {
    if (!kDebugMode) return;
    _dropTimer?.cancel();
    _dropTimer = Timer.periodic(const Duration(seconds: 5), (Timer _) async {
      final String? fc = await readProperty('frame-drop-count');
      final String? dfc = await readProperty('decoder-frame-drop-count');
      final String? vfc = await readProperty('vo-drop-frame-count');
      debugPrint('[YQK-DROP] fc=$fc decoder=$dfc vo=$vfc');
    });
  }
  /// property 写失败不能阻断播放（旧版 mpv 对个别 key 不认）
  Future<void> _safeSetProperty(String key, String value) async {
    try {
      await setProperty(key, value);
      if (kDebugMode && key == 'glsl-shaders') {
        debugPrint('[YQK-A4K] setProperty($key) ok -> "$value"');
      }
    } catch (e) {
      if (kDebugMode && key == 'glsl-shaders') {
        debugPrint('[YQK-A4K] setProperty($key) FAILED: $e');
      }
      // 忽略：让播放继续
    }
  }

  /// 头字段里不能有换行（会破坏 mpv 的列表解析）
  static String _cleanHeader(String v) =>
      v.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();

  /// 日志/异常里只留主机名，避免把 query 里的 token 打到日志（凭据不落日志）
  static String _redact(String url) {
    final Uri? u = Uri.tryParse(url);
    if (u == null) return '<无法解析的地址>';
    return '${u.scheme}://${u.host}${u.path}';
  }

  // ── 播放控制 ────────────────────────────────────────────
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration d) => _player.seek(d);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> setVolume(double v) => _player.setVolume((v * 100).clamp(0, 130));

  @override
  Future<void> setSubtitle(String? pathOrUri, {String? title}) async {
    if (pathOrUri == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    // 15 §A5：sub-add 是异步的，这里等它生效再返回，
    // 否则紧接着的 seek 会让字幕错位
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(pathOrUri, title: title ?? '外挂字幕'),
    );
    // 这套 libmpv 的字幕层把文字画在旋转 90° 的右边缘（截图 gbk3/s1/s5.png 都能看到
    // 一条竖排残影），所以字幕改由 Flutter 层自绘（subtitle_overlay.dart）。
    // 这里把 mpv 自己的字幕显示关掉，避免屏幕右下角那条错位残影。
    await _safeSetProperty('sub-visibility', 'no');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    String? sid = await readProperty('sid');
    String? text = await readProperty('sub-text');
    debugPrint('[YQK-SUB] setSubtitleTrack 之后 sid=$sid sub-text=$text');
    if ((sid == null || sid == 'no') && (text == null || text.isEmpty)) {
      // media_kit 的 setSubtitleTrack 在部分 libmpv 上不落 select，直接 sub-add 兜底
      await setProperty('sub-add', '$pathOrUri select');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      sid = await readProperty('sid');
      text = await readProperty('sub-text');
      debugPrint('[YQK-SUB] sub-add 兜底之后 sid=$sid sub-text=$text');
    }
  }

  @override
  Future<void> setSubDelay(double seconds) =>
      _safeSetProperty('sub-delay', seconds.toStringAsFixed(2));

  @override
  Future<void> setSubFontSize(double size) =>
      _safeSetProperty('sub-font-size', size.round().toString());

  @override
  bool get supportsProperties => true;

  /// Anime4K：`glsl-shaders` 传绝对路径列表，空列表=卸掉整条链。
  ///
  /// 两个实测坑（都在本机 Android 11 + media_kit 2.0.1 上复现过）：
  /// 1. 这套 libmpv 的列表分隔符是 `:`，用逗号会被当成**一个**文件名，
  ///    mpv 日志直接报 `Cannot open file '/a.glsl,/b.glsl'`，然后黑屏。
  /// 2. 不要顺手把 hwdec 切成 `mediacodec-copy`：会变成
  ///    `h264_mediacodec: Both surface and native_window are NULL`，同样黑屏。
  ///    vo=gpu 下 `hwdec=auto` 本来就能跑用户 shader。
  /// 挂/卸 Anime4K 链。注意：**在 open 之前挂**才不会把渲染面丢掉——
  /// 播放中改 glsl-shaders 会触发 vo 重建，Android 上表现为黑屏（只有声音）。
  /// 所以这里记下来，open() 里一次性带上；运行中调用就走即时设置。
  @override
  Future<void> setShaderChain(List<String> absolutePaths) async {
    _shaderChain = List<String>.unmodifiable(absolutePaths);
    if (!_opened) return;
    await setProperty('glsl-shaders', _chainValue);
  }

  List<String> _shaderChain = const <String>[];
  bool _opened = false;
  String get _chainValue => _shaderChain.join(':');

  @override
  Future<void> setProperty(String key, String value) async {
    final PlatformPlayer? p = _player.platform;
    if (p is! NativePlayer) return;
    // mpv 还没初始化完时 set_property 可能永远不返回，加超时兜住
    try {
      await p
          .setProperty(key, value)
          .timeout(kHttpConnectTimeout);
    } on TimeoutException {
      // 初始化未完成：这条属性这次就不生效了，不影响播放
    }
  }

  @override
  Future<void> dispose() async {
    _dropTimer?.cancel();
    await _events.close();
    await _error.close();
    await _player.dispose();
  }
}
