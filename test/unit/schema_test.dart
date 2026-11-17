import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';

/// 表结构守门（03 §3 DDL）。
///
/// 这条测试的意义：字段、类型、默认值、索引名字都是对外契约（迁移、备份、诊断全靠它），
/// 谁手滑删一列/改个默认值，这里立刻红。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// PRAGMA table_info 的 (name, type, notnull, dflt_value)
  Future<List<Map<String, dynamic>>> columnsOf(String table) async {
    final List<QueryRow> rows =
        await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((QueryRow r) => r.data).toList();
  }

  Future<List<String>> indexesOf(String table) async {
    final List<QueryRow> rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
          variables: <Variable<Object>>[Variable<String>(table)],
        )
        .get();
    return rows
        .map((QueryRow r) => r.read<String>('name'))
        // 主键自动索引（sqlite_autoindex_*）不是我们定义的
        .where((String n) => !n.startsWith('sqlite_autoindex'))
        .toList()
      ..sort();
  }

  test('6 张表的列名与顺序和 03 §3 完全一致', () async {
    // 先触发 onOpen（DRIFT 在建库时会跑 onCreate）
    await db.customSelect('SELECT 1').get();

    expect(
      (await columnsOf('rooms')).map((Map<String, dynamic> c) => c['name']),
      <String>[
        'id', 'name', 'code', 'mode', 'join_url', 'host_name', 'password_hash',
        'is_favorite', 'member_count', 'last_joined_at', 'created_at', 'extra',
      ],
    );
    expect(
      (await columnsOf('history')).map((Map<String, dynamic> c) => c['name']),
      <String>[
        'id', 'title', 'url', 'source_kind', 'source_id', 'poster', 'position',
        'duration', 'watched_seconds', 'episode_index', 'series_id',
        'watched_at', 'created_at', 'extra',
      ],
    );
    expect(
      (await columnsOf('favorites')).map((Map<String, dynamic> c) => c['name']),
      <String>[
        'id', 'title', 'url', 'source_kind', 'source_id', 'poster', 'tag',
        'note', 'added_at', 'extra',
      ],
    );
    expect(
      (await columnsOf('sources')).map((Map<String, dynamic> c) => c['name']),
      <String>[
        'id', 'name', 'kind', 'api_url', 'base_url', 'username', 'enabled',
        'priority', 'health', 'last_check_at', 'last_latency_ms', 'config',
        // v7 加的列：TVBox 源的 ext 原文（在 config 之后声明，所以排在这里）
        'ext',
        // v2 加的列（只加列不删列）：B 站不可恢复失败的标记
        'unreachable',
        'created_at',
      ],
    );
    expect(
      (await columnsOf('accounts')).map((Map<String, dynamic> c) => c['name']),
      <String>[
        'id', 'kind', 'display_name', 'username', 'extra', 'status',
        'last_verified', 'created_at',
      ],
    );
    expect(
      (await columnsOf('danmaku_cache'))
          .map((Map<String, dynamic> c) => c['name']),
      <String>[
        'media_id', 'episode_index', 'payload', 'count', 'fetched_at',
        'expires_at',
      ],
    );
  });

  test('默认值与索引名一个都没改', () async {
    final Map<String, Map<String, dynamic>> historyCols = <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> c in await columnsOf('history'))
        c['name'] as String: c,
    };
    // position/duration REAL NOT NULL DEFAULT 0；watched_seconds INTEGER NOT NULL DEFAULT 0
    // 注意 REAL 列的默认值在 sqlite 里存成 '0.0'，整数列是 '0'
    expect(historyCols['position']!['dflt_value'], '0.0');
    expect(historyCols['position']!['type'], 'REAL');
    expect(historyCols['duration']!['dflt_value'], '0.0');
    expect(historyCols['watched_seconds']!['type'], 'INTEGER');
    expect(historyCols['watched_seconds']!['dflt_value'], '0');
    expect(historyCols['watched_at']!['notnull'], 1);

    final Map<String, Map<String, dynamic>> sourceCols = <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> c in await columnsOf('sources'))
        c['name'] as String: c,
    };
    expect(sourceCols['enabled']!['dflt_value'], '1');
    expect(sourceCols['priority']!['dflt_value'], '0');
    expect(sourceCols['health']!['dflt_value'], "'unknown'");

    final Map<String, Map<String, dynamic>> accountCols = <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> c in await columnsOf('accounts'))
        c['name'] as String: c,
    };
    expect(accountCols['status']!['dflt_value'], "'unknown'");

    // 索引名与 DDL 一致
    expect(await indexesOf('rooms'), <String>[
      'idx_rooms_last_joined',
      'idx_rooms_mode',
    ]);
    expect(await indexesOf('history'), <String>[
      'idx_history_series',
      'idx_history_url',
      'idx_history_watched',
    ]);
    expect(await indexesOf('favorites'), <String>['idx_fav_tag', 'idx_fav_url']);
    expect(await indexesOf('sources'), <String>[
      'idx_sources_kind',
      'idx_sources_priority',
    ]);
    expect(await indexesOf('accounts'), <String>['idx_accounts_kind']);
    expect(await indexesOf('danmaku_cache'), <String>['idx_danmaku_expires']);
  });

  test('onCreate 会写入一条内置演示源', () async {
    final List<Source> rows = await db.sourceDao.all(enabledOnly: false);
    expect(rows.length, 1);
    expect(rows.single.id, 'builtin_demo');
    expect(rows.single.kind, 'direct');
  });
}
