import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/sources/source_service.dart';
import 'package:yiqikan/features/sources/search_hit_card.dart';

/// A3：F9 评分渲染分支（源名后带 `4.0★`）。
///
/// 真机上走不到：内置演示源 kind=direct 没有 apiUrl，搜索永远 0 命中，
/// 所以直接用 SearchHitCard 喂一条带评分的 hit 断言渲染。
void main() {
  SearchHit hit({String name = '演示源', String remarks = '高清'}) => SearchHit(
        sourceId: 'builtin_demo',
        sourceName: name,
        title: '测试片子',
        score: 0.9,
        remarks: remarks,
      );

  testWidgets('有评分时源名后显示 4.0★', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            SearchHitCard(hit: hit(), score: 4),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('★'), findsOneWidget);
    expect(find.textContaining('4.0★'), findsOneWidget);
    expect(find.text('演示源 4.0★ · 高清'), findsOneWidget);
  });

  testWidgets('没有评分时不出现星星', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            SearchHitCard(hit: hit(name: '没评分源', remarks: ''), score: null),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('★'), findsNothing);
    expect(find.text('没评分源'), findsOneWidget);
  });

  test('subtitleText 拼接规则', () {
    expect(
      SearchHitCard(hit: hit(), score: 5).subtitleText,
      '演示源 5.0★ · 高清',
    );
    expect(
      SearchHitCard(hit: hit(remarks: ''), score: null).subtitleText,
      '演示源',
    );
  });
}
