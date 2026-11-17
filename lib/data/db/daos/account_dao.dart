part of '../app_database.dart';

/// 网盘账号 DAO（03 §4.5）
///
/// 这张表只存"能显示的信息"，凭据一律走 `SecureStore` 的 `cred_{id}`。
@DriftAccessor(tables: <Type>[Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  Future<List<Account>> all({String? kind}) {
    final SimpleSelectStatement<$AccountsTable, Account> q = select(accounts);
    if (kind != null) {
      q.where(($AccountsTable t) => t.kind.equals(kind));
    }
    return (q
          ..orderBy(<OrderClauseGenerator<$AccountsTable>>[
            ($AccountsTable t) => OrderingTerm(expression: t.createdAt),
          ]))
        .get();
  }

  Future<Account?> byId(String id) {
    return (select(accounts)..where(($AccountsTable t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsert(Account a) => into(accounts).insertOnConflictUpdate(a);

  /// status: ok/expired/invalid/unknown
  Future<void> setStatus(String id, String status) {
    return (update(accounts)..where(($AccountsTable t) => t.id.equals(id)))
        .write(AccountsCompanion(status: Value<String>(status)));
  }

  /// 同 [RoomDao.deleteById]：不能叫 delete，会和 drift 的同名方法冲突。
  Future<void> deleteById(String id) {
    return (delete(accounts)..where(($AccountsTable t) => t.id.equals(id))).go();
  }

  /// 同 kind 下 status=ok 的第一个（按创建时间），给"默认账号"用
  Future<Account?> primaryOf(String kind) {
    return (select(accounts)
          ..where(($AccountsTable t) =>
              t.kind.equals(kind) & t.status.equals('ok'))
          ..orderBy(<OrderClauseGenerator<$AccountsTable>>[
            ($AccountsTable t) => OrderingTerm(expression: t.createdAt),
          ])
          ..limit(1))
        .getSingleOrNull();
  }
}
