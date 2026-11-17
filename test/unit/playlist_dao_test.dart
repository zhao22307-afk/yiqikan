import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';

/// F4 播放列表 DAO（内存库）：建 / 加 / 重排 / 删 / 同名拒。
void main() {
  late AppDatabase db;
  late PlaylistDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = PlaylistDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> countOf(String name) async => (await dao.items(name)).length;

  test('create 同名拒；listNames 条数只数真实条目', () async {
    expect(await dao.create('周末片单'), isTrue);
    expect(await dao.create('周末片单'), isFalse, reason: '同名列表必须被拒');

    expect(await dao.addItem('周末片单', 'http://a/1.mkv', '第一集'), isTrue);
    expect(await dao.addItem('周末片单', 'http://a/2.mkv', '第二集'), isTrue);
    expect(await dao.addItem('周末片单', 'http://a/1.mkv', '第一集'), isFalse,
        reason: '同一个 url 不能重复入列');

    final List<PlaylistSummary> l = await dao.listNames();
    expect(l.length, 1);
    expect(l.first.name, '周末片单');
    expect(l.first.count, 2, reason: '空列表的占位行不能算条数');
  });

  test('reorder 按给定 id 顺序写回 sortIndex，重进顺序不变', () async {
    await dao.create('排一下');
    await dao.addItem('排一下', 'http://b/1.mkv', '1');
    await dao.addItem('排一下', 'http://b/2.mkv', '2');
    await dao.addItem('排一下', 'http://b/3.mkv', '3');

    final List<Playlist> before = await dao.items('排一下');
    expect(before.map((Playlist r) => r.mediaTitle).toList(),
        <String>['1', '2', '3']);

    final List<String> reversed =
        before.reversed.map((Playlist r) => r.id).toList();
    await dao.reorder('排一下', reversed);

    final List<Playlist> after = await dao.items('排一下');
    expect(after.map((Playlist r) => r.id).toList(), reversed);
    expect(after.map((Playlist r) => r.mediaTitle).toList(),
        <String>['3', '2', '1']);
  });

  test('removeItem 条数 -1；remove 连条目一起删', () async {
    await dao.create('删一删');
    await dao.addItem('删一删', 'http://c/1.mkv', '1');
    await dao.addItem('删一删', 'http://c/2.mkv', '2');
    expect(await countOf('删一删'), 2);

    final List<Playlist> rows = await dao.items('删一删');
    await dao.removeItem(rows.first.id);
    expect(await countOf('删一删'), 1);

    final int n = await dao.remove('删一删');
    expect(n, greaterThan(0));
    expect((await dao.listNames()).where((PlaylistSummary s) => s.name == '删一删'),
        isEmpty);
  });

  test('rename 同名冲突被拒，改其它名字能成', () async {
    await dao.create('A');
    await dao.create('B');
    expect(await dao.rename('A', 'B'), isFalse);
    expect(await dao.rename('A', 'C'), isTrue);
    final List<String> names =
        (await dao.listNames()).map((PlaylistSummary s) => s.name).toList();
    expect(names.contains('C'), isTrue);
    expect(names.contains('A'), isFalse);
  });

  test('itemId 稳定：同参数同 id，参数变则变', () {
    final String a = PlaylistDao.itemId('周末片单', 1794600000000, 'http://x/1.mkv');
    final String b = PlaylistDao.itemId('周末片单', 1794600000000, 'http://x/1.mkv');
    final String c = PlaylistDao.itemId('周末片单', 1794600000001, 'http://x/1.mkv');
    expect(a, b);
    expect(a, isNot(c));
    expect(a.length, 16);
  });
}
