import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';

/// F11 弹幕库：收藏去重 / 按房间过滤 / 删除（内存库，不碰真机文件）。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  const String url = 'http://127.0.0.1:8080/local/media/play?path=%2Fsdcard%2FMovies%2Fa.mkv';

  test('同一条弹幕（text+mediaUrl 相同）收藏两次只落一条', () async {
    final bool first = await db.danmakuDao.favPut(
      text: '哈哈',
      mediaUrl: url,
      pos: 12.0,
      room: '195127',
      at: 1794623342245,
    );
    expect(first, isTrue);

    final bool again = await db.danmakuDao.favPut(
      text: '哈哈',
      mediaUrl: url,
      pos: 12.0,
      room: '195127',
      at: 1794623349999,
    );
    expect(again, isFalse, reason: '重复收藏应返回 false');

    expect((await db.danmakuDao.favList()).length, 1);
  });

  test('同一句话在不同片子里算两条', () async {
    await db.danmakuDao.favPut(text: '哈哈', mediaUrl: url, pos: 1, room: 'r1', at: 1);
    await db.danmakuDao.favPut(text: '哈哈', mediaUrl: 'http://x/b.mkv', pos: 2, room: 'r2', at: 2);
    expect((await db.danmakuDao.favList()).length, 2);
  });

  test('favList 按房间过滤，favRemove 删得掉', () async {
    await db.danmakuDao.favPut(text: 'a', mediaUrl: url, pos: 1, room: '195127', at: 1);
    await db.danmakuDao.favPut(text: 'b', mediaUrl: url, pos: 2, room: '587709', at: 2);

    expect((await db.danmakuDao.favList(room: '195127')).length, 1);
    expect((await db.danmakuDao.favList()).length, 2);

    final String id = (await db.danmakuDao.favList()).first.id;
    await db.danmakuDao.favRemove(id);
    expect((await db.danmakuDao.favList()).length, 1);
  });
}
