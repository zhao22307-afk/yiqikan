import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';

/// F5 标签 / F9 片源评分：v4 新表的 DAO 行为（内存库）。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  const String url = 'http://127.0.0.1:8080/local/media/play?path=%2Fa.mkv';

  test('标签 id = md5(mediaUrl+name) 前 16 位，同输入稳定', () {
    final String a = TagDao.tagId(url, '周更');
    final String b = TagDao.tagId(url, '周更');
    expect(a, b);
    expect(a.length, 16);
    expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
    // 与直接算的 md5 对齐（防止以后换算法把旧数据读不出来）
    final String manual = md5
        .convert(utf8.encode('$url\u0001周更'))
        .toString()
        .substring(0, 16);
    expect(a, manual);
    expect(TagDao.tagId(url, '日常'), isNot(a));
  });

  test('addTag 去重：同片同名只落一条，空名不落', () async {
    expect(await db.tagDao.addTag(url, '周更'), isTrue);
    expect(await db.tagDao.addTag(url, '周更'), isFalse);
    expect(await db.tagDao.addTag(url, '   '), isFalse);
    expect((await db.tagDao.byMedia(url)).length, 1);
    expect((await db.tagDao.byName('周更')).length, 1);
    expect(await db.tagDao.names(), <String>['周更']);
  });

  test('removeTag 之后 byMedia 为空', () async {
    await db.tagDao.addTag(url, '周更');
    final TagRow t = (await db.tagDao.byMedia(url)).single;
    await db.tagDao.removeTag(t.id);
    expect(await db.tagDao.byMedia(url), isEmpty);
    expect(await db.tagDao.all(), isEmpty);
  });

  test('setScore 边界裁剪：0→1、9→5、3 保持；avg 按条数算', () async {
    expect(await db.ratingDao.setScore('builtin_demo', 0), 1);
    expect((await db.ratingDao.byId('builtin_demo'))!.score, 1);
    expect(await db.ratingDao.setScore('builtin_demo', 9), 5);
    expect((await db.ratingDao.byId('builtin_demo'))!.score, 5);
    expect(await db.ratingDao.setScore('src_b', 3), 3);
    expect((await db.ratingDao.all()).length, 2);
    expect(await db.ratingDao.avg(), 4.0);
  });

  test('没评分时 avg=0（界面据此不显示星级）', () async {
    expect(await db.ratingDao.avg(), 0);
    expect(await db.ratingDao.byId('nope'), isNull);
  });
}
