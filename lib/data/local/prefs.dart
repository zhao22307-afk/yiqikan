import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';

/// SharedPreferences 键（03 §6）——只放**非敏感**设置。
///
/// 凭据（cookie/token/password）一律走 `SecureStore`，这里出现凭据即视为 bug。
/// 存储时统一加 [kPrefsPrefix]（`yiqikan_`）前缀，避免与同进程其它插件撞键。
class PrefKeys {
  const PrefKeys._();

  // ── 房间/网络（七种建房模式的默认值都在这里）──────────────
  /// 七选一默认值
  static const String defaultMode = 'default_mode';
  static const String lastRoomCode = 'last_room_code';

  /// 加入别人的地址
  static const String peer = 'peer';

  /// 云房间中继
  static const String relay = 'relay';
  static const String tunnelUrl = 'tunnel_url';
  static const String externalBackend = 'external_backend';
  static const String meshIp = 'mesh_ip';

  /// D26 通道策略：auto（默认，优先局域网）/ lanOnly / forceTunnel
  static const String channelMode = 'channel_mode';

  // ── 播放 ──────────────────────────────────────────────
  /// off/low/medium/high（Android 上一律 off，见 04 §12.6.1）
  static const String animeLevel = 'anime4k_level';

  /// 播放速度，默认 1.0
  static const String playbackSpeed = 'playback_speed';

  /// 播放内核：auto / mpv / fvp（M3，15 §A4）
  static const String kernelKind = 'kernel_kind';

  /// 默认 64
  static const String bufferSizeMb = 'buffer_size_mb';

  /// auto/mediacodec-copy/no
  static const String hwdec = 'hwdec';

  // ── 弹幕 ──────────────────────────────────────────────
  static const String danmakuEnabled = 'danmaku_enabled';
  static const String danmakuOpacity = 'danmaku_opacity';
  static const String danmakuFontSize = 'danmaku_font_size';

  /// 8 秒穿屏为 1.0
  static const String danmakuSpeed = 'danmaku_speed';

  /// JSON：关键词/等级/类型
  static const String danmakuFilter = 'danmaku_filter';

  /// 0.25/0.5/0.75/1.0
  static const String danmakuArea = 'danmaku_area';

  // ── 字幕 ──────────────────────────────────────────────
  static const String subtitleSize = 'subtitle_size';
  static const String subtitleColor = 'subtitle_color';
  static const String subtitleDelay = 'subtitle_delay';

  // ── 界面/通用 ─────────────────────────────────────────
  /// dark/light/system
  static const String themeMode = 'theme_mode';

  /// 全局字号倍率（0.9 / 1.0 / 1.15），默认 1.0（G12 大字体）
  static const String fontScale = 'font_scale';

  /// zh/en
  static const String locale = 'locale';
  static const String guideShown = 'guide_shown';
  static const String autoPlayNext = 'auto_play_next';
  static const String continueFromLast = 'continue_from_last';

  /// 默认 2048
  static const String cacheLimitMb = 'cache_limit_mb';

  /// 默认 3
  static const String downloadConcurrency = 'download_concurrency';

  /// G8 更新源（自建 JSON feed 的完整 URL；空串表示不检查）
  static const String updateFeedUrl = 'update_feed_url';

  /// G5 首启引导是否已看过（true 之后不再自动弹）
  static const String onboardingDone = 'onboarding_done';

  /// H2 翻译服务的端点（密钥走 SecureStore，不进 prefs）
  static const String translateEndpoint = 'translate_endpoint';

  /// H4 自动跳过片头（默认关，用户手动开）
  static const String chapSkipIntro = 'chap_skip_intro';

  /// H4 自动跳过片尾（默认关；命中后由上层决定播完/下一集）
  static const String chapSkipOutro = 'chap_skip_outro';

  /// 全部非敏感键（清空设置 / 导出诊断时用）
  static const List<String> all = <String>[
    defaultMode,
    lastRoomCode,
    peer,
    relay,
    tunnelUrl,
    externalBackend,
    meshIp,
    channelMode,
    animeLevel,
    playbackSpeed,
    kernelKind,
    bufferSizeMb,
    hwdec,
    danmakuEnabled,
    danmakuOpacity,
    danmakuFontSize,
    danmakuSpeed,
    danmakuFilter,
    danmakuArea,
    subtitleSize,
    subtitleColor,
    subtitleDelay,
    themeMode,
    fontScale,
    locale,
    guideShown,
    autoPlayNext,
    continueFromLast,
    cacheLimitMb,
    downloadConcurrency,
    updateFeedUrl,
    onboardingDone,
    translateEndpoint,
    chapSkipIntro,
    chapSkipOutro,
  ];

  /// 真正落盘的键名（加了 yiqikan_ 前缀）
  static String storageKey(String key) => '$kPrefsPrefix$key';
}

/// SharedPreferences 的薄封装：统一前缀 + 类型化读写 + 默认值。
///
/// 只在 [Prefs.open] 里拿一次 SharedPreferences 实例，之后全靠它读。
class Prefs {
  Prefs._(this._p);

  final SharedPreferences _p;

  static Future<Prefs> open() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return Prefs._(p);
  }

  String? getString(String key) => _p.getString(PrefKeys.storageKey(key));

  Future<void> setString(String key, String value) =>
      _p.setString(PrefKeys.storageKey(key), value);

  int? getInt(String key) => _p.getInt(PrefKeys.storageKey(key));

  Future<void> setInt(String key, int value) =>
      _p.setInt(PrefKeys.storageKey(key), value);

  double? getDouble(String key) => _p.getDouble(PrefKeys.storageKey(key));

  Future<void> setDouble(String key, double value) =>
      _p.setDouble(PrefKeys.storageKey(key), value);

  bool? getBool(String key) => _p.getBool(PrefKeys.storageKey(key));

  /// 按原样取一个值，不猜类型。
  ///
  /// 备份导出要知道某个键到底存的是 String / int / double / bool：
  /// `getString` 内部会 `as String?` 强转，遇到 double 直接抛
  /// `'double' is not a subtype of type 'String?' in type cast`。
  Object? getAny(String key) => _p.get(PrefKeys.storageKey(key));

  Future<void> setBool(String key, bool value) =>
      _p.setBool(PrefKeys.storageKey(key), value);

  Future<void> remove(String key) => _p.remove(PrefKeys.storageKey(key));

  /// 清空本 App 的键（不碰别人的）
  Future<void> clearAppKeys() async {
    for (final String key in PrefKeys.all) {
      await _p.remove(PrefKeys.storageKey(key));
    }
  }
}
