import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/room_snapshot.dart';

void main() {
  Map<String, dynamic> hello() => <String, dynamic>{
        'room': <String, dynamic>{
          'code': 'R1',
          'name': '房',
          'host': 'm_host',
          'approval': false,
          'media': <String, dynamic>{'url': 'u', 'title': 't', 'duration': 0, 'epIndex': 0},
          'state': <String, dynamic>{'playing': false, 'position': 0, 'rate': 1, 'updatedAt': 0},
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'm_host', 'nickname': '房主', 'role': 'host', 'muted': false, 'online': true},
            <String, dynamic>{'id': 'm_g', 'nickname': '客人', 'role': 'guest', 'muted': false, 'online': true},
          ],
        },
      };

  test('muted 帧更新对应成员的 muted，其它字段不动', () {
    final RoomSnapshot s = RoomSnapshot.fromHello(hello())!;
    expect(s.memberById('m_g')!.muted, isFalse);
    final RoomSnapshot s2 = s.withMemberMuted('m_g', true);
    expect(s2.memberById('m_g')!.muted, isTrue);
    expect(s2.memberById('m_host')!.muted, isFalse);
    expect(s2.seq, s.seq);
    expect(s2.code, 'R1');
    expect(s2.members.length, 2);
  });

  test('未知 memberId 的 muted 帧不改任何成员', () {
    final RoomSnapshot s = RoomSnapshot.fromHello(hello())!;
    final RoomSnapshot s2 = s.withMemberMuted('m_nobody', true);
    expect(s2.members.where((RoomMember m) => m.muted).isEmpty, isTrue);
    expect(s2.members.length, s.members.length);
  });
}
