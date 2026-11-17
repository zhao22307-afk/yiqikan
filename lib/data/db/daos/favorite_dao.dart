part of '../app_database.dart';

/// 收藏 DAO（03 §4.3）
@DriftAccessor(tables: <Type>[Favorites])
class FavoriteDao extends DatabaseAccessor<AppDatabase>
    with _$FavoriteDaoMixin {
  FavoriteDao(super.db);

  Future<void> add(Favorite f) => into(favorites).insertOnConflictUpdate(f);

  Future<void> remove(String id) {
    return (delete(favorites)..where(($FavoritesTable t) => t.id.equals(id)))
        .go();
  }

  /// 同一个 url 只收藏一次（表上还有 idx_fav_url 唯一索引兜底）
  Future<bool> exists(String url) async {
    final Favorite? hit = await (select(favorites)
          ..where(($FavoritesTable t) => t.url.equals(url))
          ..limit(1))
        .getSingleOrNull();
    return hit != null;
  }

  Future<List<Favorite>> all({String? tag}) {
    final SimpleSelectStatement<$FavoritesTable, Favorite> q =
        select(favorites);
    if (tag != null) {
      q.where(($FavoritesTable t) => t.tag.equals(tag));
    }
    return (q
          ..orderBy(<OrderClauseGenerator<$FavoritesTable>>[
            ($FavoritesTable t) =>
                OrderingTerm(expression: t.addedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// 去重后的分组名（NULL 不算分组）
  Future<List<String>> tags() async {
    final List<Favorite> rows = await select(favorites).get();
    final Set<String> seen = <String>{};
    for (final Favorite f in rows) {
      final String? tag = f.tag;
      if (tag != null && tag.trim().isNotEmpty) seen.add(tag);
    }
    final List<String> result = seen.toList()..sort();
    return result;
  }

  Future<void> setTag(String id, String? tag) {
    return (update(favorites)..where(($FavoritesTable t) => t.id.equals(id)))
        .write(FavoritesCompanion(tag: Value<String?>(tag)));
  }

  Future<void> clearAll() => delete(favorites).go();
}
