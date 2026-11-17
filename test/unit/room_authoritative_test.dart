import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/room_client.dart';
import 'package:yiqikan/platform/room/room_snapshot.dart';

RoomClient client() => RoomClient(
      baseUrl: 'http://127.0.0.1:8080',
      roomCode: 'R1',
      roomToken: 't',
      deviceName: 'test',
    );

Map<String, dynamic> stateFrame(double pos, {bool playing = false, double rate = 1, int seq = 1}) =>
    <String, dynamic>{
      'type': 'state',
      'seq': seq,
      'state': <String, dynamic>{
        'position': pos,
        'playing': playing,
        'rate': rate,
        'by': 'm_host',
      },
    };

Map<String, dynamic> helloFrame() => <String, dynamic>{
      'type': 'hello',
      'memberId': 'm_g',
      'memberToken': 'x',
      'room': <String, dynamic>{
        'code': 'R1',
        'name': '房',
        'host': 'm_host',
        'approval': false,
        'media': <String, dynamic>{'url': 'u', 'title': 't', 'duration': 0, 'epIndex': 0},
        'state': <String, dynamic>{'playing': false, 'position': 0, 'rate': 1, 'updatedAt': 0},
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'm_host', 'nickname': '房主', 'role': 'host', 'muted': false, 'online': true},
        ],
      },
    };

void main() {
  test('controlMode 解析：free 保留，缺省与 host 都回落 host', () {
    Map<String, dynamic> hello(String? mode) => <String, dynamic>{
          'room': <String, dynamic>{
            'code': 'R1',
            'name': 'r',
            'host': 'm_h',
            'control_mode': mode,
            'media': <String, dynamic>{},
            'state': <String, dynamic>{},
            'members': <dynamic>[],
          },
        };
    expect(RoomSnapshot.fromHello(hello('free'))!.controlMode, 'free');
    expect(RoomSnapshot.fromHello(hello('host'))!.controlMode, 'host');
    expect(RoomSnapshot.fromHello(hello(null))!.controlMode, 'host');
  });

  test('claim-result ok:false 写入 rejectedClaim，reason 与帧一致', () {
    final RoomClient c = client();
    c.debugFeedFrame(<String, dynamic>{
      'type': 'claim-result',
      'rid': 'r1',
      'ok': false,
      'reason': 'timeout',
    });
    expect(c.rejectedClaim.value?['reason'], 'timeout');
    c.debugFeedFrame(<String, dynamic>{'type': 'claim-result', 'rid': 'r2', 'ok': true});
    expect(c.rejectedClaim.value, isNull);
  });
  test('state 帧更新 authoritative 三元组，但不写 snapshot', () {
    final RoomClient c = client();
    c.debugFeedFrame(helloFrame());
    final RoomSnapshot? before = c.snapshot.value;
    expect(before, isNotNull);
    expect(before!.members.length, 1);

    c.debugFeedFrame(stateFrame(6, playing: false));
    expect(c.authoritativePosition, const Duration(seconds: 6));
    expect(c.authoritativePlaying, isFalse);
    expect(c.authoritativeRate, 1);
    expect(c.authoritativeBy, 'm_host');
    // snapshot 仍是 hello 那份（成员没被 state 改动）
    expect(c.snapshot.value!.members.length, 1);
    expect(c.snapshot.value!.position, 0.0);
  });

  test('authoritativePosition 按本地时钟外推（playing）', () {
    final RoomClient c = client();
    c.debugFeedFrame(helloFrame());
    c.debugFeedFrame(stateFrame(300, playing: true, rate: 1.5));
    c.debugAdvanceAuthClock(const Duration(seconds: 4));
    // 300 + 4 * 1.5 = 306
    expect(c.authoritativePosition, const Duration(milliseconds: 306000));
  });

  test('暂停时不外推', () {
    final RoomClient c = client();
    c.debugFeedFrame(helloFrame());
    c.debugFeedFrame(stateFrame(300, playing: false));
    c.debugAdvanceAuthClock(const Duration(seconds: 10));
    expect(c.authoritativePosition, const Duration(seconds: 300));
  });

  test('joined 帧带 room 时就地更新成员，不重进房', () {
    final RoomClient c = client();
    c.debugFeedFrame(helloFrame());
    expect(c.snapshot.value!.members.length, 1);

    final Map<String, dynamic> room = Map<String, dynamic>.of(
        (helloFrame()['room'] as Map).cast<String, dynamic>());
    room['members'] = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'm_host', 'nickname': '房主', 'role': 'host', 'muted': false, 'online': true},
      <String, dynamic>{'id': 'm_g2', 'nickname': '新客', 'role': 'guest', 'muted': false, 'online': true},
    ];
    c.debugFeedFrame(<String, dynamic>{'type': 'joined', 'seq': 2, 'member': <String, dynamic>{'id': 'm_g2'}, 'room': room});

    expect(c.snapshot.value!.members.length, 2);
    expect(c.snapshot.value!.memberById('m_g2'), isNotNull);
  });

  test('state 帧里的 media 记到 authoritativeMediaUrl（换片跟随用）', () {
    final RoomClient c = client();
    c.debugFeedFrame(helloFrame());
    c.debugFeedFrame(<String, dynamic>{
      'type': 'state',
      'seq': 3,
      'state': <String, dynamic>{
        'position': 0,
        'playing': true,
        'rate': 1,
        'by': 'm_host',
        'media': <String, dynamic>{'url': 'http://x/b.mp4'},
      },
    });
    expect(c.authoritativeMediaUrl, 'http://x/b.mp4');
  });

  test('同一 position 连续两帧（playing 不同）都要触发通知', () {
    final RoomClient c = client();
    c.debugFeedFrame(helloFrame());
    int fired = 0;
    c.authTick.addListener(() => fired++);

    c.debugFeedFrame(stateFrame(300, playing: true, seq: 1));
    c.debugFeedFrame(stateFrame(300, playing: false, seq: 2));

    expect(fired, 2);
    expect(c.authoritativePlaying, isFalse);
    expect(c.authoritativePosition, const Duration(seconds: 300));
  });

  test('authTick 每来一条 state 帧就递增', () {
    final RoomClient c = client();
    c.debugFeedFrame(helloFrame());
    expect(c.authTick.value, 0);

    c.debugFeedFrame(stateFrame(10, seq: 1));
    expect(c.authTick.value, 1);
    c.debugFeedFrame(stateFrame(10, seq: 2));
    expect(c.authTick.value, 2);
    c.debugFeedFrame(stateFrame(11, playing: true, rate: 2, seq: 3));
    expect(c.authTick.value, 3);
  });
}
