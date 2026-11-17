import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/features/room/room_overlay.dart';
import 'package:yiqikan/l10n/gen/app_localizations.dart';
import 'package:yiqikan/platform/room/room_snapshot.dart';

RoomSnapshot _snap({
  String hostId = 'm_host',
  List<Map<String, dynamic>>? members,
}) {
  final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
    'memberId': 'm_host',
    'memberToken': 'tok',
    'online': 1,
    'room': <String, dynamic>{
      'code': 'ROOM01',
      'name': '测试房',
      'host': hostId,
      'approval': false,
      'settings': <String, dynamic>{'maxMembers': 20, 'tag': ''},
      'media': <String, dynamic>{
        'url': 'file:///tmp/a.mkv',
        'title': 'a',
        'duration': 600.0,
        'epIndex': 0,
      },
      'state': <String, dynamic>{
        'playing': true,
        'position': 100.0,
        'rate': 1.0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      'members': members ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'm_host',
              'nickname': '房主',
              'role': 'host',
              'muted': false,
              'online': true,
              'progress': <String, dynamic>{'position': 100.0, 'playing': true},
            },
            <String, dynamic>{
              'id': 'm_guest',
              'nickname': '客人',
              'role': 'guest',
              'muted': true,
              'online': true,
              'progress': <String, dynamic>{'position': 100.0, 'playing': true},
            },
          ],
    },
  });
  return s!;
}

Widget _host(Widget child) => MaterialApp(
      // G1：房主条/成员条的文案走 L（多语言），测试里要挂上委托
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Scaffold(
        body: Stack(children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          child,
        ]),
      ),
    );

void main() {
  testWidgets('MemberBar 成员条：固定第一个 chip + 其余可横向滚动，不换行',
      (WidgetTester tester) async {
    final ValueNotifier<RoomSnapshot?> snap =
        ValueNotifier<RoomSnapshot?>(_snap());
    await tester.pumpWidget(_host(RoomMemberBar(snapshot: snap, memberId: 'm_guest')));
    await tester.pump();

    // 自己（客人）固定在左侧，房主在可滚动列表里
    expect(find.text('客人'), findsOneWidget);
    expect(find.text('房主'), findsWidgets);
    // 横向列表存在、没有换成两行（高度固定 30）
    expect(find.byType(ListView), findsOneWidget);
    final ListView lv = tester.widget<ListView>(find.byType(ListView));
    expect(lv.scrollDirection, Axis.horizontal);
    expect(tester.getSize(find.byType(RoomMemberBar)).height, lessThanOrEqualTo(30));
    // 不再有「点一下就收成胶囊」的整条点击（那会吃掉滚动手势）
    expect(find.text('2 人在看'), findsNothing);
  });

  testWidgets('HostBar 只对房主渲染，且只留房主专属动作（无播放键/进度条）',
      (WidgetTester tester) async {
    final ValueNotifier<RoomSnapshot?> snap =
        ValueNotifier<RoomSnapshot?>(_snap());

    await tester.pumpWidget(_host(RoomHostBar(
      snapshot: snap,
      memberId: 'm_host',
    )));
    await tester.pump();
    expect(find.textContaining('房主控制'), findsOneWidget);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
    // M8 收口：播放/暂停与进度条回视频内的主控制层，房主条不再有第二个 Slider
    expect(find.byType(Slider), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);

    await tester.pumpWidget(_host(RoomHostBar(
      snapshot: snap,
      memberId: 'm_guest',
    )));
    await tester.pump();
    expect(find.textContaining('房主控制'), findsNothing);
  });

  testWidgets('FollowBar 用传入的实时位置算落差，无落差时 shrink', (WidgetTester tester) async {
    final ValueNotifier<RoomSnapshot?> snap =
        ValueNotifier<RoomSnapshot?>(_snap());
    Duration mine = const Duration(seconds: 100);

    await tester.pumpWidget(_host(RoomFollowBar(
      snapshot: snap,
      memberId: 'm_guest',
      isHost: false,
      expected: () => const Duration(seconds: 100),
      myPosition: () => mine,
    )));
    await tester.pump();
    expect(find.textContaining('你落后'), findsNothing);

    // 本机只播到 70 秒（不是靠 members[].progress），应出现「你落后 30 秒」
    mine = const Duration(seconds: 70);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('你落后'), findsOneWidget);
  });
}
