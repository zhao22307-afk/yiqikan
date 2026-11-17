import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';

/// 观看历史的增量累加语义（03 §3.2 + §4.2）。
///
/// 这三条是这个数据层最容易写错的地方：
///  * watched_seconds 是"看过多久"的增量累加，不是 position 的副本；
///  * 回退进度不能把统计减回去；
///  * 片尾 10 秒内算看完，位置清零，下次从头播。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> record({
    required double position,
    required double duration,
  }) {
    return db.historyDao.record(
      id: 'm_1',
      title: '测试片',
      url: 'http://127.0.0.1:8080/local/media/1.mp4',
      sourceKind: 'direct',
      position: position,
      duration: duration,
    );
  }

  test('a) 120s 看成 130s → watched_seconds 只加 10', () async {
    await record(position: 120, duration: 3600);

    final History? first = await db.historyDao.byId('m_1');
    expect(first, isNotNull);
    // 首次记录只落位置，不凭"从 0 拖到 120"补计时
    expect(first!.watchedSeconds, 0);

    await record(position: 130, duration: 3600);

    final History? second = await db.historyDao.byId('m_1');
    expect(second!.watchedSeconds, 10);
    expect(second.position, 130);
  });

  test('b) 回退到 10s → watched_seconds 不减少', () async {
    await record(position: 120, duration: 3600);
    await record(position: 130, duration: 3600);

    await record(position: 10, duration: 3600);

    final History? row = await db.historyDao.byId('m_1');
    expect(row!.watchedSeconds, 10); // 只增不减
    expect(row.position, 10); // 位置跟着用户走
  });

  test('c) 位置进入片尾 10 秒内 → 位置清零，下次从头播', () async {
    await record(position: 120, duration: 3600);
    await record(position: 130, duration: 3600);

    // 3595 > 3600 - 10，算看完
    await record(position: 3595, duration: 3600);

    final History? row = await db.historyDao.byId('m_1');
    expect(row!.position, 0);
    // 这一次跳转按 60 秒封顶累计（130 → 3595 真实差 3465，clamp 到 60）
    expect(row.watchedSeconds, 70);
  });
}
