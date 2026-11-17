import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';
import 'package:yiqikan/data/sources/source_service.dart';
import 'package:yiqikan/data/sources/tvbox_config.dart';
import 'package:yiqikan/data/sources/tvbox_importer.dart';

/// P1c：外部配置导入（贴地址 / 粘 JSON 都走 importFrom）。
///
/// 这里只钉住三件事：
///  * 只有 csp / maccms 被导入，js / py / other 只统计；
///  * 幂等（第二次 added=0，skip 数等于可用数）；
///  * ext 原样落库、kind 按类型分流，id 稳定可复用。
void main() {
  late AppDatabase db;
  late SourceService service;
  late TvboxImporter importer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SourceService(dao: db.sourceDao);
    importer = TvboxImporter(service: service);
  });

  tearDown(() async {
    await db.close();
  });

  /// 建库时会插一条 builtin_demo，本文件只关心导入进来的那些。
  Future<List<Source>> imported() async =>
      (await db.sourceDao.all(enabledOnly: false))
          .where((Source s) => s.id.startsWith('tvbox_'))
          .toList();

  String config(List<Map<String, Object?>> sites) =>
      jsonEncode(<String, Object?>{'sites': sites});

  Map<String, Object?> csp(String key, [String ext = '']) => <String, Object?>{
        'key': key,
        'name': '测试 $key',
        'type': 3,
        'api': 'csp_$key',
        'ext': ext,
      };

  Map<String, Object?> jsSite(String key) => <String, Object?>{
        'key': key,
        'name': 'JS $key',
        'type': 3,
        'api': 'drpy_$key',
        'ext': '',
      };

  Map<String, Object?> pySite(String key) => <String, Object?>{
        'key': key,
        'name': 'PY $key',
        'type': 3,
        'api': './py/$key.py',
        'ext': '',
      };

  Map<String, Object?> maccms(String key) => <String, Object?>{
        'key': key,
        'name': '采集 $key',
        'type': 1,
        'api': 'https://$key.example.com/api.php/provide/vod/',
        'ext': '',
      };

  test('只导入 csp，js/py 不计入', () async {
    final String raw = config(<Map<String, Object?>>[csp('A'), jsSite('B'), pySite('C')]);
    final int added = await importer.importFrom(raw, label: 'test');
    expect(added, 1);
    final List<Source> rows = await imported();
    expect(rows.map((Source s) => s.apiUrl).toList(), <String>['csp_A']);
  });

  test('type=1 落成 maccms，type=3 落成 tvbox', () async {
    final String raw =
        config(<Map<String, Object?>>[csp('A'), maccms('vod')]);
    expect(await importer.importFrom(raw, label: 'test'), 2);
    final List<Source> rows = await imported();
    final Map<String, String> byApi = <String, String>{
      for (final Source s in rows) s.apiUrl ?? '': s.kind,
    };
    expect(byApi['csp_A'], SourceKind.tvbox.name);
    expect(byApi['https://vod.example.com/api.php/provide/vod/'],
        SourceKind.maccms.name);
  });

  test('ext 原样落库', () async {
    final String raw = config(<Map<String, Object?>>[csp('A', '{"site":"x"}')]);
    await importer.importFrom(raw, label: 'test');
    final List<Source> rows = await imported();
    expect(rows.single.ext, '{"site":"x"}');
  });

  test('ext 为空时是空串，不是 null', () async {
    await importer.importFrom(config(<Map<String, Object?>>[csp('A')]),
        label: 'test');
    final List<Source> rows = await imported();
    expect(rows.single.ext, '');
  });

  test('same config twice → added=0 第二条', () async {
    final String raw =
        config(<Map<String, Object?>>[csp('A'), csp('B'), csp('C')]);
    expect(await importer.importFrom(raw, label: 'test'), 3);
    expect(await importer.importFrom(raw, label: 'test'), 0);
    expect((await imported()).length, 3);
  });

  test('不同 ext 同一 api 视为两条', () async {
    final String raw = config(<Map<String, Object?>>[
      csp('A', 'e1'),
      csp('A', 'e2'),
    ]);
    expect(await importer.importFrom(raw, label: 'test'), 2);
  });

  test('id 稳定：同 key 重复导入命中同一行', () async {
    final String first = config(<Map<String, Object?>>[csp('A', 'e1')]);
    final String second = config(<Map<String, Object?>>[csp('A', 'e1')]);
    await importer.importFrom(first, label: 'test');
    await importer.importFrom(second, label: 'test');
    final List<Source> rows = await imported();
    expect(rows.length, 1);
    expect(rows.single.id, startsWith('tvbox_'));
  });

  test('中文 key 不会塌成同一个 id', () async {
    final String raw = config(<Map<String, Object?>>[
      csp('配置中心'),
      csp('本地'),
      csp('预告'),
    ]);
    expect(await importer.importFrom(raw, label: 'test'), 3);
    final List<Source> rows = await imported();
    expect(rows.map((Source s) => s.id).toSet().length, 3);
  });

  test('onlyUsable=false 时 js 也进库', () async {
    final String raw = config(<Map<String, Object?>>[csp('A'), jsSite('B')]);
    expect(await importer.importFrom(raw, onlyUsable: false, label: 'test'), 2);
  });

  test('空 sites 数组 → 0 条、不抛', () async {
    final String raw = config(<Map<String, Object?>>[]);
    expect(await importer.importFrom(raw, label: 'test'), 0);
    expect(await imported(), isEmpty);
  });

  test('坏 JSON → 0 条、不抛', () async {
    expect(await importer.importFrom('not json', label: 'test'), 0);
    expect(await imported(), isEmpty);
  });

  test('非 TVBox 结构（无 sites）→ 0 条', () async {
    final String raw = jsonEncode(<String, Object?>{'api': 'x', 'version': 1});
    expect(await importer.importFrom(raw, label: 'test'), 0);
  });

  test('preview：total 与 usable 的差就是 js/py/other', () async {
    final String raw = config(<Map<String, Object?>>[
      csp('A'),
      csp('B'),
      jsSite('C'),
      pySite('D'),
      maccms('e'),
    ]);
    final List<TvboxSite> parsed = TvboxConfig.parse(raw);
    expect(parsed.length, 5);
    expect(parsed.where(TvboxConfig.usable).length, 3);
  });

  test('导入的行默认 enabled=1 / health=unknown', () async {
    await importer.importFrom(config(<Map<String, Object?>>[csp('A')]),
        label: 'test');
    final Source s = (await imported()).single;
    expect(s.enabled, 1);
    expect(s.health, 'unknown');
    expect(s.unreachable, 0);
  });
}
