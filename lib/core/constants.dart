/// 全局常量表 —— 数值来自《03_架构与数据模型.md》§11，一个都不许改。
///
/// 任何需要在 Dart 与 Java 内置服务之间对齐的数值、标识都放这里，
/// 禁止在业务代码里写字面量。
library;

// ============================================================
// 身份标识（00 §0 / 03 §0）—— 与 Android 侧必须逐字一致
// ============================================================

/// 应用显示名，也是自建页面品牌行的固定前缀。
const String kAppName = '一起看';

/// 当前版本号（与 android/app/build.gradle.kts 的 versionName 保持一致）。
/// G8 更新检查拿它跟 feed 里的 version 做语义版本比较。
const String kAppVersion = '1.0.0';

/// 自建页面品牌行（页脚/登录页/管理端统一使用）。
const String kBrandLine = '一起看 · 本机服务';

/// 深链 scheme：yiqikan://room/{code}?pwd=xxx
const String kDeepLinkScheme = 'yiqikan';

/// SharedPreferences 前缀。
const String kPrefsPrefix = 'yiqikan_';

/// 本机数据库文件名。
const String kDbName = 'yiqikan.db';

// ============================================================
// 同步协议（房间 / 心跳 / 漂移）
// ============================================================

/// 协议版本号，客户端与服务端不同版本直接拒绝入房。
const int kProtocolVersion = 1;

/// 房间状态广播间隔。
const int kStateIntervalMs = 500;

/// 心跳发送间隔。
const int kPingIntervalMs = 2000;

/// 心跳超时（超过即判定对端掉线）。
const int kPongTimeoutMs = 6000;

/// 同步 seek 的保护窗口：窗口内忽略自身回声，防抖。
const int kSeekGuardMs = 300;

/// 软漂移阈值：超过则微调播放速率。
const int kSoftDriftMs = 300;

/// 硬漂移阈值：超过则直接 seek。
const int kHardDriftMs = 700;

/// 软漂移时的速率微调步长（±5%）。
const double kRateNudge = 0.05;

/// 房主掉线宽限期，期内不夺权。
const int kHostOfflineGraceMs = 2500;

/// 单房间最大成员数。
const int kMaxMembers = 20;

/// 单次建房最大媒体条目数。
const int kMaxMedia = 200;

/// 房间内同类操作的冷却时间（防连点刷屏）。
const int kActionCooldownMs = 300;

/// 断线重连最大次数。
const int kReconnectMax = 5;

/// 重连指数退避基数（秒）。
const int kReconnectBaseSec = 1;

// ============================================================
// 局域网发现 / 内置服务端口
// ============================================================

/// UDP 广播发现端口。
const int kDiscoveryPort = 45231;

/// 发现广播间隔（秒）。
const int kDiscoveryIntervalSec = 1;

/// 发现广播 TTL（秒）。
const int kDiscoveryTtlSec = 15;

/// 同一设备的去重窗口（秒）。
const int kDiscoveryDedupSec = 6;

/// 内置 HTTP/WS 服务候选端口：8080..8089 共 10 个连续端口。
const List<int> kServerPortRange = <int>[
  8080,
  8081,
  8082,
  8083,
  8084,
  8085,
  8086,
  8087,
  8088,
  8089,
];

/// 内置 STUN 端口。
const int kStunPort = 3478;

// ============================================================
// 弹幕
// ============================================================

/// 单条弹幕在屏时长（秒）。
const double kDanmakuDisplaySec = 8.0;

/// 弹幕轨道数上限。
const int kDanmakuMaxTracks = 12;

/// 单条轨道高度（逻辑像素）。
const double kDanmakuTrackHeight = 26.0;

/// 同屏弹幕条数上限。
const int kDanmakuMaxOnScreen = 80;

/// 本机弹幕缓存条数上限。
const int kDanmakuCacheLimit = 2000;

// ============================================================
// 播放 / 缓存
// ============================================================

/// 播放器默认缓冲区大小（MB）。
const int kDefaultBufferMb = 64;

/// 硬 seek 阈值（毫秒）：超过直接 seek，不再微调。
const int kHardSeekThresholdMs = 700;

/// 掉帧统计窗口（毫秒）。
const int kFrameDropWindowMs = 3000;

/// 窗口内掉帧数超过该值判定为卡顿。
const int kFrameDropThreshold = 45;

/// 边下边播流缓存上限（MB）。
const int kStreamCacheLimitMb = 2048;

/// 图片缓存上限（MB）。
const int kImageCacheLimitMb = 256;

// ============================================================
// 超时（七条 MUST 之一：请求必须带超时）
// ============================================================

/// HTTP 连接超时：8s。
const Duration kHttpConnectTimeout = Duration(seconds: 8);

/// HTTP 读取超时：20s。
const Duration kHttpReadTimeout = Duration(seconds: 20);

/// DNS/地址解析超时：15s。
const Duration kResolveTimeout = Duration(seconds: 15);

/// 嗅探超时：20s。
const Duration kSniffTimeout = Duration(seconds: 20);

/// 内置服务冷启动就绪等待：5s。
const Duration kServerBootTimeout = Duration(seconds: 5);

// ============================================================
// 传输 / 分片
// ============================================================

/// 单文件上传上限（MB）。
const int kMaxUploadMb = 4096;

/// 单次上传总量上限（MB）。
const int kMaxUploadTotalMb = 16384;

/// 分片大小（MB）。
const int kChunkSizeMb = 4;
