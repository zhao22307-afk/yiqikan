import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';
import 'package:yiqikan/data/db/library_dao.dart';

/// F1 追番（tag='follow'）的单值语义（内存库，不碰真机文件）。
void main() {
  late AppDatabase db;
  late LibraryDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = LibraryDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  const LibraryMedia film = LibraryMedia(
    title: '演示番剧',
    url: 'http://127.0.0.1:8080/local/media/play?path=%2Fsdcard%2FMovies%2Fb.mkv',
    sourceKind: 'local',
  );

  test('markFollow 追番 → 收藏列表里不出现，追番列表里有', () async {
    expect(await dao.markFollow(film), isTrue);
    expect(await dao.isFollowing(film.url), isTrue);
    final List<Favorite> follows = await dao.listFollowing();
    expect(follows.length, 1);
    expect(follows.single.tag, LibraryDao.followTag);
    // 收藏列表要把它滤掉，否则同一部片会同时出现在两处
    expect(await dao.listFavorites(), isEmpty);
  });

  test('收藏后追番：tag 变成 follow（追番优先），再取消追番回到收藏', () async {
    await dao.toggleFavorite(film);
    expect((await dao.listFavorites()).length, 1);

    expect(await dao.markFollow(film), isTrue);
    expect(await dao.listFavorites(), isEmpty);
    expect((await dao.listFollowing()).length, 1);

    // 取消追番 = 清 tag，行不删 → 回到普通收藏
    final String id = (await dao.listFollowing()).single.id;
    await dao.unfollow(id);
    expect(await dao.listFollowing(), isEmpty);
    expect((await dao.listFavorites()).length, 1);
  });

  test('再点一次 markFollow = 取消追番', () async {
    expect(await dao.markFollow(film), isTrue);
    expect(await dao.markFollow(film), isFalse);
    expect(await dao.listFollowing(), isEmpty);
  });
}
