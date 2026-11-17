part of '../app_database.dart';

/// 片源配置 DAO（03 §4.4）
///
/// 密码不在表里：`SecureStore` 的 `source_pwd_{id}` 才是唯一存放处。
@DriftAccessor(tables: <Type>[Sources])
class SourceDao extends DatabaseAccessor<AppDatabase> with _$SourceDaoMixin {
  SourceDao(super.db);

  /// 默认只返回启用的；priority 越大越优先，同优先级按创建时间先来后到
  Future<List<Source>> all({bool enabledOnly = true}) {
    final SimpleSelectStatement<$SourcesTable, Source> q = select(sources);
    if (enabledOnly) {
      q.where(($SourcesTable t) => t.enabled.equals(1));
    }
    return (q
          ..orderBy(<OrderClauseGenerator<$SourcesTable>>[
            ($SourcesTable t) =>
                OrderingTerm(expression: t.priority, mode: OrderingMode.desc),
            ($SourcesTable t) => OrderingTerm(expression: t.createdAt),
          ]))
        .get();
  }

  Future<Source?> byId(String id) {
    return (select(sources)..where(($SourcesTable t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsert(Source s) => into(sources).insertOnConflictUpdate(s);

  Future<void> setEnabled(String id, bool on) {
    return (update(sources)..where(($SourcesTable t) => t.id.equals(id)))
        .write(SourcesCompanion(enabled: Value<int>(on ? 1 : 0)));
  }

  Future<void> setPriority(String id, int p) {
    return (update(sources)..where(($SourcesTable t) => t.id.equals(id)))
        .write(SourcesCompanion(priority: Value<int>(p)));
  }

  /// health: ok/slow/down/unknown
  Future<void> updateHealth(String id, String health, int latencyMs) {
    return (update(sources)..where(($SourcesTable t) => t.id.equals(id)))
        .write(SourcesCompanion(
      health: Value<String>(health),
      lastLatencyMs: Value<int?>(latencyMs),
      lastCheckAt: Value<int?>(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// 同 [RoomDao.deleteById]：不能叫 delete，会和 drift 的同名方法冲突。
  Future<void> deleteById(String id) {
    return (delete(sources)..where(($SourcesTable t) => t.id.equals(id))).go();
  }

  /// 按给定顺序重排：列表头 priority 最高
  Future<void> reorder(List<String> idsInOrder) async {
    await transaction(() async {
      final int total = idsInOrder.length;
      for (int i = 0; i < total; i++) {
        await (update(sources)
              ..where(($SourcesTable t) => t.id.equals(idsInOrder[i])))
            .write(SourcesCompanion(priority: Value<int>(total - i)));
      }
    });
  }

  /// 这个 kind 下有没有被标记「不可恢复解析失败」的源（-10403/87007/87008 落地）
  Future<bool> anyUnreachable(String kind) async {
    final List<Source> rows = await (select(sources)
          ..where((Sources t) => t.kind.equals(kind) & t.unreachable.equals(1))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// 标记/清标记。原 App 只对「不可恢复」的失败写标记，用户手动重试才清
  Future<void> setUnreachableByKind(String kind, bool value) {
    return (update(sources)..where((Sources t) => t.kind.equals(kind)))
        .write(SourcesCompanion(unreachable: Value<int>(value ? 1 : 0)));
  }
}
