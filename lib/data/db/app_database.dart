import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../domain/entities/danmaku.dart';
import '../../domain/entities/watch_stats.dart';
import 'tables.dart';

part 'app_database.g.dart';

// 6 个 DAO 都是本 library 的 part：这样它们能直接看到生成的数据类（Room/History/…），
// 又不会和 app_database.dart 互相 import 形成环。
part 'daos/account_dao.dart';
part 'daos/danmaku_dao.dart';
part 'daos/favorite_dao.dart';
part 'daos/history_dao.dart';
part 'daos/room_dao.dart';
part 'daos/source_dao.dart';
part 'daos/subtitle_dao.dart';
part 'daos/tag_dao.dart';
part 'daos/rating_dao.dart';
part 'daos/playlist_dao.dart';
part 'chapter_mark_dao.dart';

/// 本地库：6 张表 + 6 个 DAO（03 §3 / §4）。
///
/// 全项目只有一个 AppDatabase 实例（providers/databaseProvider 里持有），
/// 测试用 [AppDatabase.forTesting] 注入内存库，不碰真机文件。
@DriftDatabase(
  tables: <Type>[
    Rooms,
    HistoryTable,
    Favorites,
    Sources,
    Accounts,
    DanmakuCacheTable,
    Subtitles,
    Tags,
    SourceRatings,
    Playlists,
    ChapterMarks,
  ],
  daos: <Type>[
    RoomDao,
    HistoryDao,
    FavoriteDao,
    SourceDao,
    AccountDao,
    DanmakuDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 真机/桌面：落在应用支持目录下的 yiqikan.db
  AppDatabase() : super(_openConnection());

  /// 测试用：注入任意 QueryExecutor（通常是 NativeDatabase.memory()）
  AppDatabase.forTesting(super.e);

  /// 字幕库（F12）。没有进 @DriftDatabase 的 daos 列表：drift_dev 只认它自己
  /// 生成过 $XxxTable 的 DAO，字幕表是 v3 新加的，手写一个就够，省一次生成。
  late final SubtitleDao subtitleDao = SubtitleDao(this);

  /// 标签库（F5）/ 片源评分（F9）：同一个理由，v4 新表，手动挂 DAO。
  late final TagDao tagDao = TagDao(this);
  late final RatingDao ratingDao = RatingDao(this);

  /// 播放列表（F4）：v5 新表，同样手动挂 DAO。
  late final PlaylistDao playlistDao = PlaylistDao(this);

  /// 手动片头/片尾标记（H4）：v6 新表，同样手动挂 DAO。
  late final ChapterMarkDao chapterMarkDao = ChapterMarkDao(this);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // 初始数据：内置一条演示源，保证首页第一次打开不是空列表
          await into(sources).insert(
            SourcesCompanion.insert(
              id: 'builtin_demo',
              name: '内置演示',
              kind: 'direct',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        },
        // v1 还没有升级路径。以后改表结构：只加列不删列，每次 +1 版本号，
        // 并按 03 §14 的写法在这里补 `if (from < N) { await m.addColumn(...) }`。
        onUpgrade: (Migrator m, int from, int to) async {
          debugPrint('[YQK-DB] upgrade $from -> $to');
          // v2: sources 加 unreachable（只加列不删列，03 §14）
          if (from < 2) {
            await m.addColumn(sources, sources.unreachable);
          }
          // v3: 新增 subtitles（F12 字幕库）。只 createTable，不动任何旧表。
          if (from < 3) {
            await m.createTable(subtitles);
          }
          // v4: 新增 tags（F5 标签）+ source_ratings（F9 评分）。同样只 createTable。
          if (from < 4) {
            await m.createTable(tags);
            await m.createTable(sourceRatings);
          }
          // v5: 新增 playlists（F4 播放列表）。同样只 createTable，旧表一行不动。
          if (from < 5) {
            await m.createTable(playlists);
          }
          // v6: 新增 chapter_marks（H4 手动片头/片尾）。前五段顺序不动。
          if (from < 6) {
            await m.createTable(chapterMarks);
          }
          // v7: sources 加 ext（TVBox 源的 ext 原文）。只加列，前六段顺序不动。
          if (from < 7) {
            await m.addColumn(sources, sources.ext);
          }
        },
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );
}

/// 数据库文件位置：应用支持目录 / yiqikan.db（不在公共存储，不进备份白名单）
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationSupportDirectory();
    final File file = File(p.join(dir.path, kDbName));
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    return NativeDatabase.createInBackground(file);
  });
}
