import 'package:flutter/widgets.dart';

import '../../domain/media_chapter.dart';

/// 打开媒体时的进阶参数（防盗链 / 代理 / 自签证书）。
///
/// 只有 mpv 内核能全部兑现；其它内核会退化成「只带 headers 的 open」，
/// 这样后面 M3 接 fvp 内核时不用改调用方（15 §A4）。
class MediaOpenOptions {
  const MediaOpenOptions({
    this.headers = const <String, String>{},
    this.httpProxy,
    this.tlsVerify,
    this.properties = const <String, String>{},
  });

  /// 请求头：Referer / Origin / User-Agent / Cookie
  ///
  /// 记住铁律：Cookie 是凭据，只允许通过这里的请求头传给内核，
  /// 不许写进日志、不许落 pref。
  final Map<String, String> headers;

  /// 例：http://127.0.0.1:7890 或 socks5://127.0.0.1:1080
  final String? httpProxy;

  /// false → mpv `tls-verify=no`（自签证书站点）
  final bool? tlsVerify;

  /// 其它要透传给内核的 mpv property
  final Map<String, String> properties;

  static const MediaOpenOptions none = MediaOpenOptions();
}

/// 内核事件：统一成一种类型，调用方不用依赖 media_kit 的类型。
enum PlaybackEventKind {
  opened,
  position,
  duration,
  playing,
  buffering,
  error,
  completed,
}

@immutable
class PlaybackEvent {
  const PlaybackEvent(
    this.kind, {
    this.position,
    this.duration,
    this.playing,
    this.message,
  });

  final PlaybackEventKind kind;
  final Duration? position;
  final Duration? duration;
  final bool? playing;

  /// 只放人话错误原因；不放任何请求头 / Cookie（凭据不落日志）
  final String? message;

  @override
  String toString() => 'PlaybackEvent($kind, pos=$position, '
      'dur=$duration, playing=$playing, msg=$message)';
}

/// 音轨条目（05 §3.2「音轨」弹层要显示语言标记 + 声道数）
@immutable
class AudioTrackInfo {
  const AudioTrackInfo({
    required this.index,
    required this.label,
    this.language,
    this.channels,
  });

  /// 内核内的轨序号（mpv 的 aid / fvp 的 stream index）
  final int index;

  /// 给人看的名字，例如「日语 · AAC · 2 声道」
  final String label;

  /// ISO 639 语言标记（可能为空，文件里没写元数据）
  final String? language;

  /// 声道数（可能为空）
  final int? channels;

  @override
  String toString() => label;
}

/// 播放内核抽象（15 §A4）。
///
/// M2 只实现 mpv 内核；M3 补 fvp（MDK）与软件解码内核，切内核时保留 position。
abstract class PlaybackKernel {
  /// 内核名，用于日志/诊断页
  String get name;

  /// 统一事件流
  Stream<PlaybackEvent> get events;

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<String> get errorStream;

  Duration get position;
  Duration get duration;
  bool get playing;
  bool get buffering;

  /// 视频画面（mpv 是纹理，fvp 是 platform view）
  /// 画面显示比例（宽/高），已含 SAR 修正（mpv 的 dw/dh、fvp 的显示尺寸）。
  /// 未知时返回 null —— 上层自己决定退什么比例（现在退 16:9）。
  /// 注意：两个后端都必须是「显示尺寸」，别一个用编码尺寸，否则变形片源会差一截。
  double? get videoAspect;

  Widget buildVideo({BoxFit fit = BoxFit.contain});

  /// 打开媒体。
  ///
  /// [start] 是续播起点；[play] false 时打开后停在首帧。
  Future<void> open(
    String url, {
    MediaOpenOptions options = MediaOpenOptions.none,
    Duration start = Duration.zero,
    bool play = true,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<void> setRate(double rate);
  Future<void> setVolume(double v);

  /// 挂字幕。null = 关闭字幕；可以是本地路径、file:// 或 http(s) 地址
  Future<void> setSubtitle(String? pathOrUri, {String? title});

  /// 字幕延迟（秒，可负）
  Future<void> setSubDelay(double seconds);

  /// 字幕字号（mpv sub-font-size，默认 42）
  Future<void> setSubFontSize(double size);

  /// 内嵌音轨名（mpv 有；fvp 返回空）
  List<String> get audioTrackNames;

  /// 音轨详情（语言 + 声道），05 §3.2 的「音轨」弹层用
  List<AudioTrackInfo> get audioTracks;
  int get currentAudioTrack;
  Future<void> setAudioTrack(int index);

  /// 外挂音轨（15 §A6 / 13 §A6′）：把本地音频文件挂成一条额外音轨。
  ///
  /// mpv 走 `audio-file` 属性，挂上之后 `audioTracks` 会多出一条，
  /// 用户再在音轨弹层里选它（写 aid）。不支持的内核抛 [UnsupportedError]。
  Future<void> addExternalAudio(String path);

  /// 选中「最后一条」音轨：外挂音轨（audio-file）挂上后它一定排在 track-list 最后。
  /// 不按数组下标猜，是因为 mpv 里外挂轨与内嵌轨的顺序不保证。
  Future<void> selectLastAudioTrack();

  /// 内嵌字幕轨名
  List<String> get subtitleTrackNames;
  Future<void> setSubtitleTrack(int index);

  /// 字幕延迟/字号是否真的能改（fvp 只能改字号，延迟无效 → false）
  bool get supportsSubtitleTuning;

  /// 画面比例：>0 = 强制该比例（如 16/9），<=0 = 用源比例。
  /// mpv 写 video-aspect-override，fvp 走 setAspectRatio。
  Future<void> setAspectRatio(double ratio);

  /// 高级面板用：一次性读一批诊断属性。不支持的键返回 null（面板显示 —）
  Future<Map<String, String?>> debugProperties(List<String> keys);

  /// 设置内核属性（mpv 有；其它内核忽略）
  /// 挂/卸 Anime4K：传绝对路径列表，空列表=卸掉（04 §12.2 的三档链由 Anime4k 决定）
  Future<void> setShaderChain(List<String> absolutePaths);

  Future<void> setProperty(String key, String value);

  /// 读回一个属性（诊断/验收用：frame-drop-count 这类只能在运行中读）
  Future<String?> readProperty(String key);

  bool get supportsProperties;

  /// H4：片源自带的章节表（只读）。
  ///
  /// 默认空表：没有章节 API 的内核（fvp）不需要实现任何东西。
  /// 拿到的是「已排序、end 已算好」的列表，上层直接用。
  Future<List<MediaChapter>> chapters() async => const <MediaChapter>[];

  Future<void> dispose();
}
