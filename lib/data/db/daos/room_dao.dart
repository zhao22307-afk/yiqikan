part of '../app_database.dart';

/// 房间历史 DAO（03 §4.1）
@DriftAccessor(tables: <Type>[Rooms])
class RoomDao extends DatabaseAccessor<AppDatabase> with _$RoomDaoMixin {
  RoomDao(super.db);

  /// 最近开过/进过的房间，按最后进入时间倒序
  Future<List<Room>> recent({int limit = 20}) {
    return (select(rooms)
          ..orderBy(<OrderClauseGenerator<$RoomsTable>>[
            ($RoomsTable t) =>
                OrderingTerm(expression: t.lastJoinedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  /// 收藏的房间
  Future<List<Room>> favorites() {
    return (select(rooms)
          ..where(($RoomsTable t) => t.isFavorite.equals(1))
          ..orderBy(<OrderClauseGenerator<$RoomsTable>>[
            ($RoomsTable t) =>
                OrderingTerm(expression: t.lastJoinedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<Room?> byId(String id) {
    return (select(rooms)..where(($RoomsTable t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 房间号会复用，所以取"最近一次进入"的那条
  Future<Room?> byCode(String code) {
    return (select(rooms)
          ..where(($RoomsTable t) => t.code.equals(code))
          ..orderBy(<OrderClauseGenerator<$RoomsTable>>[
            ($RoomsTable t) =>
                OrderingTerm(expression: t.lastJoinedAt, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> upsert(Room room) => into(rooms).insertOnConflictUpdate(room);

  /// 进入房间时刷新时间戳。
  /// 人数要由房间同步的真实快照写回（签名里没有 count 参数，不能瞎加一）。
  Future<void> touchJoined(String id) {
    return (update(rooms)..where(($RoomsTable t) => t.id.equals(id))).write(
      RoomsCompanion(
        lastJoinedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> setFavorite(String id, bool on) {
    return (update(rooms)..where(($RoomsTable t) => t.id.equals(id))).write(
      RoomsCompanion(isFavorite: Value<int>(on ? 1 : 0)),
    );
  }

  /// 注意：不能叫 `delete` —— drift 的 `DatabaseAccessor.delete(TableInfo)` 同名，
  /// Dart 不支持按参数区分重载，所以这里用 `deleteById`。
  Future<void> deleteById(String id) {
    return (delete(rooms)..where(($RoomsTable t) => t.id.equals(id))).go();
  }

  Future<void> clearAll() => delete(rooms).go();
}
