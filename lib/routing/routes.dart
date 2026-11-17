/// 路由表 —— 42 条路径常量，来自《03_架构与数据模型.md》§8，字符串不许改。
///
/// 用法：跳转一律 `context.go(Routes.xxx)`，禁止裸写字符串。
class Routes {
  const Routes._();

  // ---------- 启动 / 引导 ----------
  static const String splash = '/';
  static const String guide = '/guide';

  // ---------- 首页 / 搜索 ----------
  static const String home = '/home';
  static const String search = '/search';
  static const String searchResult = '/search/result';

  // ---------- 详情 / 选集 ----------
  static const String detail = '/media/:id';
  static const String episodes = '/media/:id/episodes';

  // ---------- 播放器 ----------
  static const String player = '/player';
  static const String playerSet = '/player/settings';
  static const String danmakuSet = '/player/danmaku';
  static const String subtitleSet = '/player/subtitle';

  /// 播放器高级面板（15 §A11，只在 debug 构建可见）
  static const String playerAdvanced = '/player/advanced';

  // ---------- 片源 / 采集规则 ----------
  static const String sources = '/sources';
  static const String sourceAdd = '/sources/add';

  /// P1c 导入配置（贴地址 / 粘 JSON / 单个源）
  static const String sourceImport = '/sources/import';

  /// P09 网页嗅探（M5）
  static const String sniff = '/sniff';
  static const String sourceDetail = '/sources/:id';
  static const String rules = '/rules';
  static const String ruleEdit = '/rules/:id';

  // ---------- 番剧日历 ----------
  static const String calendar = '/calendar';
  static const String bangumi = '/bangumi/:id';

  // ---------- 一起看（房间）----------
  static const String roomHub = '/room';
  static const String roomJoin = '/room/join';
  static const String roomQr = '/room/qr';
  static const String room = '/room/:code';
  static const String roomMembers = '/room/:code/members';
  static const String roomSettings = '/room/:code/settings';
  static const String roomChat = '/room/:code/chat';
  static const String roomVote = '/room/:code/vote';

  // ---------- 网盘 / 自建媒体库 ----------
  static const String netdisk = '/netdisk';
  static const String netdiskAdd = '/netdisk/add';
  static const String netdiskBrowse = '/netdisk/browse';
  static const String netdiskKind = '/netdisk/:kind';
  static const String embyAccounts = '/netdisk/emby';
  static const String webdavConfig = '/netdisk/webdav';
  static const String alistConfig = '/netdisk/alist';

  // ---------- 下载 / 我的 ----------
  static const String downloads = '/downloads';
  static const String favorites = '/favorites';
  static const String history = '/history';
  static const String stats = '/stats';

  /// F3 媒体库（E6 B 组）
  static const String mediaLibrary = '/media-library';

  // ---------- 设置 ----------
  static const String settings = '/settings';
  static const String playerPref = '/settings/player';
  static const String networkPref = '/settings/network';
  static const String diag = '/settings/diag';
  static const String logs = '/settings/logs';
  static const String about = '/settings/about';
  static const String byo = '/settings/byo';
}
