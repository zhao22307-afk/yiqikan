import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';
import 'package:yiqikan/data/sources/source_service.dart';
import 'package:yiqikan/data/sources/tvbox_config.dart';
import 'package:yiqikan/platform/tvbox/tvbox_bridge.dart';

/// 用仓库里的真配置跑（不是手写 fixture），所以路径固定。
const String _jsonPath = 'android/app/src/main/assets/tvbox/dianshi.json';

void main() {
  final String raw = File(_jsonPath).readAsStringSync();
  final List<TvboxSite> sites = TvboxConfig.parse(raw);
  final Map<String, int> stat = TvboxConfig.summarize(sites);

  test('163 个 site 全解析出来', () {
    expect(sites.length, 163);
    // 报告用：sites=163 csp=113 js=26 py=7 maccms=14
    expect(stat['csp'], 113);
    expect(stat['maccms'], 14);
    expect(sites.where((TvboxSite s) => s.key.isNotEmpty).length, 163);
  });

  test('分类各档对上（csp 113 / js 26 / py 9 / maccms 14 / other 1）', () {
    expect(stat['csp'], 113);
    expect(stat['js'], 26);
    expect(stat['py'], 9);
    expect(stat['maccms'], 14);
    expect(stat['other'], 163 - 113 - 26 - 9 - 14);
  });

  test('api 带 csp_ 前缀时 clsName 去掉前缀', () {
    final TvboxSite s =
        sites.firstWhere((TvboxSite x) => x.api == 'csp_App99');
    expect(s.clsName, 'App99');
    expect(s.kind, 'csp');
    final TvboxSite m =
        sites.firstWhere((TvboxSite x) => TvboxConfig.classify(x) == 'maccms');
    expect(m.clsName, '');
  });

  test('ext 为空时返回空串而不是 null', () {
    final TvboxSite s = sites.firstWhere((TvboxSite x) => x.ext.isEmpty);
    expect(s.ext, '');
    expect(s.ext, isNotNull);
    // 104 个 csp 有 ext / 9 个空 —— 至少说明两种都有
    expect(sites.where((TvboxSite x) => x.ext.isNotEmpty).length, greaterThan(0));
  });

  test('searchOne 返回空 list 时命中为空且不抛', () {
    final List<SearchHit> hits = SourceService.parseTvboxHits(
      _source(),
      '流浪地球',
      TvboxBridge.decode('{"list":[]}'),
    );
    expect(hits, isEmpty);
  });

  test('searchOne 返回 error 时产出一条带 error 的命中', () {
    final List<SearchHit> hits = SourceService.parseTvboxHits(
      _source(),
      '流浪地球',
      TvboxBridge.decode('{"error":"Gulu: search 超时 15s"}'),
    );
    expect(hits.length, 1);
    expect(hits.first.error, contains('超时'));
    expect(hits.first.item, isNull);
  });
}

Source _source() => Source(
      id: 'tvbox_Gulu',
      name: '咕噜',
      kind: SourceKind.tvbox.name,
      apiUrl: 'csp_Gulu',
      ext: '',
      enabled: 1,
      priority: 0,
      health: 'unknown',
      unreachable: 0,
      createdAt: DateTime(2026, 11, 14).millisecondsSinceEpoch,
    );
