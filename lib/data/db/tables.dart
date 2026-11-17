import 'package:drift/drift.dart';

/// 6 张表的 Drift 定义。
///
/// 字段名、类型、默认值、索引严格对齐 03 §3 的 DDL：
/// 一个字段都不许省，索引名一个都不许改（迁移脚本与备份工具依赖这些名字）。
/// Drift 默认把 camelCase 列名转成 snake_case，所以这里写 joinUrl 落库就是 join_url。

/// `rooms` —— 房间历史（03 §3.1）
///
/// [code] 会复用，不能做唯一键；[id] 才是唯一。
/// [passwordHash] 只存 sha256，绝不存明文口令。
@DataClassName('Room')
@TableIndex(name: 'idx_rooms_last_joined', columns: {#lastJoinedAt})
@TableIndex(name: 'idx_rooms_mode', columns: {#mode})
class Rooms extends Table {
  /// 'r_abc123'
  TextColumn get id => text()();

  /// 房间名
  TextColumn get name => text()();

  /// 6 位数字房间号
  TextColumn get code => text()();

  /// lan/direct/cloud/backend/embedded/tunnel/mesh
  TextColumn get mode => text()();

  /// 上次可用地址（可能已失效，失败再重算）
  TextColumn get joinUrl => text().nullable()();

  /// 房主昵称
  TextColumn get hostName => text().nullable()();

  /// 口令 sha256（固定盐）
  TextColumn get passwordHash => text().nullable()();

  /// 0/1
  IntColumn get isFavorite => integer().withDefault(const Constant(0))();

  IntColumn get memberCount => integer().withDefault(const Constant(0))();

  /// 毫秒时间戳
  IntColumn get lastJoinedAt => integer()();

  IntColumn get createdAt => integer()();

  /// JSON 扩展（房间背景 / 公告等）
  TextColumn get extra => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `history` —— 观看历史（03 §3.2）
///
/// `position` 会回退，`watchedSeconds` 只增：续播看前者，统计看后者。
/// 表类名不能叫 History（会和数据类 History 撞名），用 tableName getter 落库为 history。
@DataClassName('History')
@TableIndex(name: 'idx_history_watched', columns: {#watchedAt})
@TableIndex(name: 'idx_history_series', columns: {#seriesId})
@TableIndex(name: 'idx_history_url', columns: {#url}, unique: true)
class HistoryTable extends Table {
  /// 落库表名 history（03 §3.2 的 DDL 名字，不能跟着类名走）
  @override
  String get tableName => 'history';

  /// 用 media url 的 md5 前 16 位
  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get url => text()();

  /// direct/bilibili/quark/emby/webdav/alist/maccms
  TextColumn get sourceKind => text()();

  /// 该源内的 id（bvid / fid / itemId）
  TextColumn get sourceId => text().nullable()();

  TextColumn get poster => text().nullable()();

  /// 秒
  RealColumn get position => real().withDefault(const Constant(0))();

  /// 秒
  RealColumn get duration => real().withDefault(const Constant(0))();

  /// 累计观看秒数（增量累加 clamp(0,60)，不是等于 position）
  IntColumn get watchedSeconds =>
      integer().withDefault(const Constant(0))();

  /// 第几集（0 开始）
  IntColumn get episodeIndex => integer().nullable()();

  /// 所属剧集 id（同剧不同集共享）
  TextColumn get seriesId => text().nullable()();

  /// 最后观看时间（毫秒）
  IntColumn get watchedAt => integer()();

  IntColumn get createdAt => integer()();

  TextColumn get extra => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `favorites` —— 收藏（03 §3.3）
@DataClassName('Favorite')
@TableIndex(name: 'idx_fav_url', columns: {#url}, unique: true)
@TableIndex(name: 'idx_fav_tag', columns: {#tag})
class Favorites extends Table {
  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get url => text()();

  TextColumn get sourceKind => text()();

  TextColumn get sourceId => text().nullable()();

  TextColumn get poster => text().nullable()();

  /// 用户自定义分组
  TextColumn get tag => text().nullable()();

  /// 备注
  TextColumn get note => text().nullable()();

  IntColumn get addedAt => integer()();

  TextColumn get extra => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `sources` —— 片源配置（03 §3.4）
///
/// 密码不在这张表里，在 SecureStore：key = 'source_pwd_{id}'。
/// api_url 不做唯一键——同一个采集站可能配两次（不同分类）。
@DataClassName('Source')
@TableIndex(name: 'idx_sources_kind', columns: {#kind})
@TableIndex(name: 'idx_sources_priority', columns: {#priority})
class Sources extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// maccms/tvbox/emby/webdav/alist/direct
  TextColumn get kind => text()();

  /// 采集站 api
  TextColumn get apiUrl => text().nullable()();

  /// 站点根
  TextColumn get baseUrl => text().nullable()();

  TextColumn get username => text().nullable()();

  IntColumn get enabled => integer().withDefault(const Constant(1))();

  /// 越大越优先
  IntColumn get priority => integer().withDefault(const Constant(0))();

  /// ok/slow/down/unknown
  TextColumn get health =>
      text().withDefault(const Constant('unknown'))();

  IntColumn get lastCheckAt => integer().nullable()();

  IntColumn get lastLatencyMs => integer().nullable()();

  /// JSON：额外配置（headers/proxy 等）
  TextColumn get config => text().nullable()();

  /// TVBox 源的 ext 原文（type=3 的 csp_xxx 靠它初始化；其它源留空）
  TextColumn get ext => text().nullable()();

  /// 1 = 这个源被标记为「不可恢复解析失败」（地区限制/版权/大会员）
  /// 标记后不再自动打接口，用户手动点「仍要重试」才清（原 App 的 unreachable）
  IntColumn get unreachable => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `accounts` —— 网盘账号（不含凭据）（03 §3.5）
///
/// 凭据一律在 SecureStore：'cred_{id}' -> JSON {cookie|token|password}。
@DataClassName('Account')
@TableIndex(name: 'idx_accounts_kind', columns: {#kind})
class Accounts extends Table {
  TextColumn get id => text()();

  /// quark/pan115/pan123/tianyi/emby/webdav/alist
  TextColumn get kind => text()();

  /// 用户备注名
  TextColumn get displayName => text()();

  /// 账号（用于显示）
  TextColumn get username => text().nullable()();

  /// JSON：serverUrl/deviceId 等非敏感信息
  TextColumn get extra => text().nullable()();

  /// ok/expired/invalid/unknown
  TextColumn get status =>
      text().withDefault(const Constant('unknown'))();

  IntColumn get lastVerified => integer().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `danmaku_cache` —— 弹幕缓存（03 §3.6）
@DataClassName('DanmakuRow')
@TableIndex(name: 'idx_danmaku_expires', columns: {#expiresAt})
class DanmakuCacheTable extends Table {
  /// 落库表名 danmaku_cache（03 §3.6 的 DDL 名字，不能跟着类名走）
  @override
  String get tableName => 'danmaku_cache';

  /// 与 history.id 对应
  TextColumn get mediaId => text()();

  IntColumn get episodeIndex => integer().withDefault(const Constant(0))();

  /// JSON 数组
  TextColumn get payload => text()();

  IntColumn get count => integer()();

  IntColumn get fetchedAt => integer()();

  IntColumn get expiresAt => integer()();

  @override
  Set<Column> get primaryKey => {mediaId, episodeIndex};
}

/// `subtitles` —— 字幕库（F12）：本地文件或在线地址二选一。
///
/// 只在 v3 migration 里 createTable，不动任何旧表（03 §14）。
@DataClassName('SubtitleRow')
class Subtitles extends Table {
  /// md5(mediaUrl + lang + (path ?? url)) 前 16 位
  TextColumn get id => text()();

  /// 归属哪个片子（与 history.url 同一套）
  TextColumn get mediaUrl => text()();

  TextColumn get lang => text().withDefault(const Constant('zh'))();

  /// 显示名，如「简体中文」「ASS 特效」
  TextColumn get label => text()();

  /// 本地绝对路径
  TextColumn get path => text().nullable()();

  /// 在线地址
  TextColumn get url => text().nullable()();

  TextColumn get format => text().withDefault(const Constant('srt'))();

  IntColumn get addedAt => integer()();

  IntColumn get lastUsedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// `tags` —— 自定义标签（F5）：一条片子可以有多个标签。
///
/// 只在 v4 migration 里 createTable，不动任何旧表（03 §14）。
@DataClassName('TagRow')
@TableIndex(name: 'idx_tags_media', columns: {#mediaUrl})
@TableIndex(name: 'idx_tags_name', columns: {#name})
class Tags extends Table {
  /// md5(mediaUrl + name) 前 16 位
  TextColumn get id => text()();

  /// 归属哪个片子（与 history.url 同一套）
  TextColumn get mediaUrl => text()();

  /// 标签文本，如「周更」「收藏夹」
  TextColumn get name => text()();

  /// 颜色（ARGB），默认主题蓝
  IntColumn get color => integer().withDefault(const Constant(0xFF4884EE))();

  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `source_ratings` —— 片源评分（F9）：用户对每个源打的分（1–5）。
///
/// 只在 v4 migration 里 createTable，不动任何旧表（03 §14）。
class SourceRatings extends Table {
  /// 与 sources.id 对应
  TextColumn get sourceId => text()();

  /// 1..5
  IntColumn get score => integer()();

  IntColumn get ratedAt => integer()();

  @override
  Set<Column> get primaryKey => {sourceId};
}

/// `playlists` —— 用户自建的播放列表（F4）。
///
/// 一个列表 = 一批 `mediaUrl`，靠 `sortIndex` 保序；列表本身不单独建表，
/// 「有哪些列表」直接从本表 `GROUP BY name` 得出（同名不允许，见 PlaylistDao）。
/// 只在 v5 migration 里 createTable，不动任何旧表（03 §14）。
class Playlists extends Table {
  /// md5(name + '|' + addedAt + '|' + mediaUrl) 前 16 位
  TextColumn get id => text()();

  /// 列表名（同名不允许）
  TextColumn get name => text()();

  /// 条目指向的片子（与 history.url 同一套）
  TextColumn get mediaUrl => text()();

  /// 条目显示名（片名/集名）
  TextColumn get mediaTitle => text().nullable()();

  /// 列表内顺序，越小越靠前
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// `chapter_marks` —— 手动标的片头/片尾（H4，v6 新表）。
///
/// 片源自带章节走 mpv 的 chapter-list（只读，不进库）；这张表只存**用户自己标的**
/// 两个点：片头结束、片尾开始，单位秒，-1 = 未设。同一个片子只有一行。
/// 只在 v6 migration 里 createTable，前五段 migration 原样不动（03 §14）。
class ChapterMarks extends Table {
  /// 复用 LibraryMedia.id 规则：md5(url) 前 16 位（同片换源不复用）
  TextColumn get mediaId => text()();

  /// 片头结束（秒）；-1 = 未设
  RealColumn get introEnd => real().withDefault(const Constant(-1))();

  /// 片尾开始（秒）；-1 = 未设
  RealColumn get outroStart => real().withDefault(const Constant(-1))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {mediaId};
}
