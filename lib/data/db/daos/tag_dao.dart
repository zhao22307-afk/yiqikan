part of '../app_database.dart';

/// F5 标签（10 号 :143）：一条片子可以有多个标签，标签名可复用到多条片子上。
///
/// 表在 v4 migration 里 createTable 出来（只加表，不动旧表）。
/// 日志由调用方打（本 library 不 import flutter，见 app_database.dart 顶部）。
class TagDao {
  TagDao(this._db);

  final AppDatabase _db;

  /// 标签 id = md5(mediaUrl + name) 前 16 位，与 library_dao.dart 同一套算法
  static String tagId(String mediaUrl, String name) {
    final Digest d = md5.convert(utf8.encode('$mediaUrl\u0001$name'));
    return d.toString().substring(0, 16);
  }

  /// 加一个标签；已存在同名同片则返回 false（不重复插）
  Future<bool> addTag(String mediaUrl, String name,
      {int? color}) async {
    final String n = name.trim();
    if (n.isEmpty) return false;
    final String id = tagId(mediaUrl, n);
    final TagRow? old = await byId(id);
    if (old != null) return false;
    await _db.into(_db.tags).insert(
          TagsCompanion.insert(
            id: id,
            mediaUrl: mediaUrl,
            name: n,
            color: Value<int>(color ?? 0xFF4884EE),
            addedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return true;
  }

  Future<TagRow?> byId(String id) {
    return (_db.select(_db.tags)..where((Tags t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> removeTag(String id) async {
    await (_db.delete(_db.tags)..where((Tags t) => t.id.equals(id))).go();
  }

  /// 某片子的全部标签（按加入时间正序，界面上稳定）
  Future<List<TagRow>> byMedia(String mediaUrl) {
    return (_db.select(_db.tags)
          ..where((Tags t) => t.mediaUrl.equals(mediaUrl))
          ..orderBy(<OrderClauseGenerator<$TagsTable>>[
            ($TagsTable t) => OrderingTerm.asc(t.addedAt),
          ]))
        .get();
  }

  /// 同名标签下的所有片子
  Future<List<TagRow>> byName(String name) {
    return (_db.select(_db.tags)
          ..where((Tags t) => t.name.equals(name))
          ..orderBy(<OrderClauseGenerator<$TagsTable>>[
            ($TagsTable t) => OrderingTerm.desc(t.addedAt),
          ]))
        .get();
  }

  Future<List<TagRow>> all() {
    return (_db.select(_db.tags)
          ..orderBy(<OrderClauseGenerator<$TagsTable>>[
            ($TagsTable t) => OrderingTerm.desc(t.addedAt),
          ]))
        .get();
  }

  /// 去重后的标签名（收藏页顶部筛选用）
  Future<List<String>> names() async {
    final List<TagRow> rows = await all();
    final List<String> out = <String>[];
    for (final TagRow r in rows) {
      if (!out.contains(r.name)) out.add(r.name);
    }
    out.sort();
    return out;
  }
}
