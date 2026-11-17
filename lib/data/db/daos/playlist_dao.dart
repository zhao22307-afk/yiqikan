part of '../app_database.dart';

/// F4 播放列表（10 号 :142）。
///
/// 一张表存条目，列表名就是 `name` 列：「有哪些列表」用 `GROUP BY name` 现算，
/// 不另建列表表——同名列表天然不允许，也就没有「空列表」这种状态。
/// 表在 v5 migration 里 createTable 出来（只加表，不动旧表）。
/// 日志由调用方打（本 library 不 import flutter，见 app_database.dart 顶部）。
class PlaylistDao {
  PlaylistDao(this._db);

  final AppDatabase _db;

  /// 条目 id = md5(name|addedAt|mediaUrl) 前 16 位；同一列表同一条片子再点一次
  /// 不会重复（调用方先查 items）。
  static String itemId(String name, int addedAt, String mediaUrl) {
    final Digest d = md5.convert(utf8.encode('$name|$addedAt|$mediaUrl'));
    return d.toString().substring(0, 16);
  }

  /// 列表清单：[{name, count}]，按名字排在界面上稳定
  Future<List<PlaylistSummary>> listNames() async {
    final List<Playlist> rows = await allItems();
    final Map<String, int> counts = <String, int>{};
    for (final Playlist r in rows) {
      counts[r.name] = counts[r.name] ?? 0;
      if (r.mediaUrl.isEmpty) continue; // 占位条目（空列表的壳）不计条数
      counts[r.name] = (counts[r.name] ?? 0) + 1;
    }
    final List<String> names = counts.keys.toList()..sort();
    return <PlaylistSummary>[
      for (final String n in names)
        PlaylistSummary(name: n, count: counts[n] ?? 0),
    ];
  }

  /// 某列表的全部条目（sortIndex 升序；同序再按 addedAt，保证「拖完重进」顺序稳定）
  Future<List<Playlist>> items(String name) {
    return (_db.select(_db.playlists)
          ..where((Playlists p) => p.name.equals(name) & p.mediaUrl.isNotValue(''))
          ..orderBy(<OrderClauseGenerator<$PlaylistsTable>>[
            ($PlaylistsTable p) => OrderingTerm.asc(p.sortIndex),
            ($PlaylistsTable p) => OrderingTerm.asc(p.addedAt),
          ]))
        .get();
  }

  Future<List<Playlist>> allItems() => _db.select(_db.playlists).get();

  /// 新建列表：同名已存在返回 false
  Future<bool> create(String name) async {
    final String n = name.trim();
    if (n.isEmpty) return false;
    final List<PlaylistSummary> all = await listNames();
    if (all.any((PlaylistSummary s) => s.name == n)) return false;
    // 空列表没法只靠 items 表表示，插一条「占位」条目指向空 url；
    // 界面上按 mediaUrl 为空过滤掉，条数也不计它。
    await _db.into(_db.playlists).insert(
          PlaylistsCompanion.insert(
            id: itemId(n, DateTime.now().millisecondsSinceEpoch, ''),
            name: n,
            mediaUrl: '',
            sortIndex: const Value<int>(0),
            addedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return true;
  }

  /// 改名：目标名已存在则拒
  Future<bool> rename(String from, String to) async {
    final String t = to.trim();
    if (t.isEmpty || t == from) return false;
    final List<PlaylistSummary> all = await listNames();
    if (all.any((PlaylistSummary s) => s.name == t)) return false;
    await _db.customUpdate(
      'UPDATE playlists SET name = ? WHERE name = ?',
      variables: <Variable<Object>>[Variable<String>(t), Variable<String>(from)],
      updates: <TableInfo<Table, dynamic>>{_db.playlists},
    );
    return true;
  }

  /// 删列表：条目一起删
  Future<int> remove(String name) async {
    return (_db.delete(_db.playlists)
          ..where((Playlists p) => p.name.equals(name)))
        .go();
  }

  /// 往列表里加一条；同列表同 url 已存在返回 false
  Future<bool> addItem(String name, String url, String title) async {
    final String n = name.trim();
    if (n.isEmpty || url.isEmpty) return false;
    final List<Playlist> cur = await items(n);
    if (cur.any((Playlist r) => r.mediaUrl == url)) return false;
    final int now = DateTime.now().millisecondsSinceEpoch;
    int maxSort = -1;
    for (final Playlist r in cur) {
      if (r.sortIndex > maxSort) maxSort = r.sortIndex;
    }
    await _db.into(_db.playlists).insert(
          PlaylistsCompanion.insert(
            id: itemId(n, now, url),
            name: n,
            mediaUrl: url,
            mediaTitle: Value<String?>(title.isEmpty ? null : title),
            sortIndex: Value<int>(maxSort + 1),
            addedAt: now,
          ),
        );
    return true;
  }

  Future<void> removeItem(String id) async {
    await (_db.delete(_db.playlists)..where((Playlists p) => p.id.equals(id)))
        .go();
  }

  /// 拖完排序：按给定的 id 顺序重写 sortIndex
  Future<void> reorder(String name, List<String> orderedIds) async {
    for (int i = 0; i < orderedIds.length; i++) {
      await (_db.update(_db.playlists)
            ..where((Playlists p) => p.id.equals(orderedIds[i])))
          .write(PlaylistsCompanion(sortIndex: Value<int>(i)));
    }
  }

  /// 去重后的列表名（播放页「加入列表…」直接用）
  Future<List<String>> names() async {
    final List<PlaylistSummary> all = await listNames();
    return <String>[for (final PlaylistSummary s in all) s.name];
  }
}

/// 列表清单的一行：名字 + 条数（占位条目不计）
class PlaylistSummary {
  const PlaylistSummary({required this.name, required this.count});

  final String name;
  final int count;
}
