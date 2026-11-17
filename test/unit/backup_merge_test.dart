import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yiqikan/data/db/app_database.dart';
import 'package:yiqikan/features/settings/backup_merge.dart';

/// F7 备份导入的合并语义（内存库）：只补不覆盖、第二次导入全跳过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> sample() => <String, Object?>{
        'app': 'yiqikan',
        'version': 1,
        'sources': <Object?>[
          <String, Object?>{
            'id': 'src_bk',
            'name': '备份里的源',
            'kind': 'direct',
            'apiUrl': null,
            'createdAt': 1,
          },
        ],
        'favorites': <Object?>[
          <String, Object?>{
            'id': 'fav0000000000001',
            'title': '片子 A',
            'url': 'http://x/a.mkv',
            'sourceKind': 'direct',
            'tag': 'later',
            'addedAt': 2,
          },
        ],
        'history': <Object?>[
          <String, Object?>{
            'id': 'his0000000000001',
            'title': '片子 A',
            'url': 'http://x/a.mkv',
            'sourceKind': 'direct',
            'position': 30.0,
            'duration': 600.0,
            'watchedAt': 3,
            'createdAt': 3,
          },
        ],
        'settings': <String, Object?>{},
      };

  test('删掉的源导入后补回来，第二次导入全部跳过', () async {
    final Map<String, Map<String, int>> first =
        await BackupMerger.merge(db, sample());
    expect(first['added']!['src'], 1);
    expect(first['added']!['fav'], 1);
    expect(first['added']!['his'], 1);
    expect(first['skipped']!['src'], 0);
    // 内置演示源 + 备份里这一条 = 2
    expect((await db.select(db.sources).get()).length, 2);
    expect((await db.select(db.historyTable).get()).length, 1);

    final Map<String, Map<String, int>> second =
        await BackupMerger.merge(db, sample());
    expect(second['added']!['src'], 0);
    expect(second['added']!['fav'], 0);
    expect(second['added']!['his'], 0);
    expect(second['skipped']!['src'], 1);
    expect(second['skipped']!['fav'], 1);
    expect(second['skipped']!['his'], 1);
    // 只有一份，没有重复插入（sources 里仍是 内置演示 + 备份那条）
    expect((await db.select(db.sources).get()).length, 2);
    expect((await db.select(db.favorites).get()).length, 1);
    expect((await db.select(db.historyTable).get()).length, 1);
  });

  test('导入不会覆盖已有条目的字段', () async {
    await BackupMerger.merge(db, sample());
    await (db.update(db.favorites)).write(
      const FavoritesCompanion(tag: Value<String?>('follow')),
    );
    await BackupMerger.merge(db, sample());
    final Favorite f = (await db.select(db.favorites).get()).single;
    expect(f.tag, 'follow'); // 仍是我改过的值，没被备份里的 later 盖掉
  });
}
