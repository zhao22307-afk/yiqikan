import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/local/secure_store.dart';
import '../data/netdisk/netdisk_account_store.dart';
import '../data/sources/source_service.dart';
import '../domain/resolver.dart';

/// 全 App 一份数据库（03 §2.1：只有 data 层碰 Drift）。
///
/// 用 `Provider` 而不是全局单例：测试里可以 override 成内存库。
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (Ref ref) {
    final AppDatabase db = AppDatabase();
    ref.onDispose(db.close);
    return db;
  },
  name: 'appDatabase',
);

/// 片源管理 + 健康检查 + 聚合搜索
final Provider<SourceService> sourceServiceProvider = Provider<SourceService>(
  (Ref ref) => SourceService(dao: ref.watch(appDatabaseProvider).sourceDao),
  name: 'sourceService',
);

/// 六级解析链（M4 只实现 direct + bilibili）
final Provider<Resolver> resolverProvider = Provider<Resolver>(
  (Ref ref) {
    final SourceDao dao = ref.watch(appDatabaseProvider).sourceDao;
    return Resolver(
      // 原 App 的 unreachable：B 站命中地区/会员限制后不再打接口，用户手动重试才清
      bilibiliBlocked: () => dao.anyUnreachable('bilibili'),
      markBilibiliBlocked: () => dao.setUnreachableByKind('bilibili', true),
    );
  },
  name: 'resolver',
);

/// 网盘账号（Drift 存能显示的、SecureStore 存凭据）
final Provider<NetdiskAccountStore> netdiskStoreProvider =
    Provider<NetdiskAccountStore>(
  (Ref ref) => NetdiskAccountStore(
    db: ref.watch(appDatabaseProvider),
    secure: SecureStore(),
  ),
  name: 'netdiskStore',
);
