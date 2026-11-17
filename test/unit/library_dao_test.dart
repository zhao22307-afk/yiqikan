import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';
import 'package:yiqikan/data/db/library_dao.dart';

/// F1 收藏 / 稍后看 / 历史 的 DAO 行为（内存库，不碰真机文件）。
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
    title: '演示片',
    url: 'http://127.0.0.1:8080/local/media/play?path=%2Fsdcard%2FMovies%2Fa.mkv',
    sourceKind: 'local',
  );

  test('toggleFavorite 两个来回：收藏→取消，列表跟着变', () async {
    expect(await dao.isFavorite(film.url), isFalse);
    expect(await dao.toggleFavorite(film), isTrue);
    expect(await dao.isFavorite(film.url), isTrue);
    expect((await dao.listFavorites()).length, 1);

    expect(await dao.toggleFavorite(film), isFalse);
    expect((await dao.listFavorites()), isEmpty);
  });

  test('稍后看与收藏互不混入（tag=later）', () async {
    await dao.markWatchLater(film);
    expect((await dao.listWatchLater()).length, 1);
    expect((await dao.listFavorites()), isEmpty);
    expect((await dao.listWatchLater()).single.tag, LibraryDao.laterTag);
  });

  test('upsertHistory 同 url 只留一条，进度按最后写入', () async {
    await dao.upsertHistory(film, const Duration(seconds: 12),
        duration: const Duration(seconds: 600), roomCode: '123456');
    await dao.upsertHistory(film, const Duration(seconds: 30),
        duration: const Duration(seconds: 600));
    final List<History> rows = await dao.listHistory();
    expect(rows.length, 1);
    expect(rows.single.position, closeTo(30, 0.01));
    expect(rows.single.duration, closeTo(600, 0.01));
  });
}
