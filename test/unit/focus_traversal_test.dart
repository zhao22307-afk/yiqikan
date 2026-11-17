import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// G3（TV 适配）没有 TV 设备可验，用这条测试证明「D-pad 左右键按视觉顺序走焦点」
/// 这件事在 Flutter 侧确实成立：同样的 `ReadingOrderTraversalPolicy` +
/// 从左到右排布的按钮，按 arrowRight 焦点会从第 1 个走到第 2 个。
///
/// 页面里用的是同一个 policy（首页整页、播放页控制条），所以这条测试是
/// 「焦点代码写法正确」的证据，不是「TV 真机可用」的证据。
void main() {
  testWidgets('ReadingOrderTraversalPolicy：左右键在三个按钮间移动焦点', (WidgetTester tester) async {
    final List<FocusNode> nodes = <FocusNode>[
      FocusNode(debugLabel: 'a'),
      FocusNode(debugLabel: 'b'),
      FocusNode(debugLabel: 'c'),
    ];
    addTearDown(() {
      for (final FocusNode n in nodes) {
        n.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < 3; i++)
                    IconButton(
                      focusNode: nodes[i],
                      autofocus: i == 0,
                      onPressed: () {},
                      icon: const Icon(Icons.circle),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(nodes[0].hasPrimaryFocus, isTrue, reason: 'autofocus 应落在第一个按钮');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(nodes[1].hasPrimaryFocus, isTrue, reason: '右移一格');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(nodes[2].hasPrimaryFocus, isTrue, reason: '再右移一格');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(nodes[1].hasPrimaryFocus, isTrue, reason: '左移回来');
  });
}
