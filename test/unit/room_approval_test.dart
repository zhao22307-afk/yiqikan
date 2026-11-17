import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/room_client.dart';
import 'package:yiqikan/platform/room/room_snapshot.dart';

/// C3/C4 的客户端契约：
/// - 房主发 approve / reject 帧（type + id + rid，seq 由服务端编号）
/// - joined / members 帧就地重建快照（批准后变多、拒绝后变少）
/// - error{code:not_host} 透传，不许崩
/// - 4004 room_full 不重连
class _FakeTransport implements RoomTransport {
  _FakeTransport(this.uri);

  final Uri uri;
  final StreamController<String> ctrl = StreamController<String>();
  final List<String> sent = <String>[];
  int? _closeCode;

  @override
  Stream<String> get messages => ctrl.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close([int code = 1000, String reason = '']) async {
    _closeCode = code;
    await ctrl.close();
  }

  void push(Map<String, dynamic> j) => ctrl.add(jsonEncode(j));

  Future<void> drop([int? code]) async {
    _closeCode = code;
    await ctrl.close();
  }
}

RoomClient _client(List<_FakeTransport> made) => RoomClient(
      baseUrl: 'http://127.0.0.1:18081',
      roomCode: '654321',
      roomToken: 'tk',
      deviceName: 'probe',
      transportFactory: (Uri uri) async {
        final _FakeTransport t = _FakeTransport(uri);
        made.add(t);
        return t;
      },
    );

Map<String, dynamic> _room(List<Map<String, dynamic>> members) => <String, dynamic>{
      'code': '654321',
      'name': '验收房',
      'host': members.isEmpty ? '' : members.first['id'],
      'approval': true,
      'control_mode': 'host',
      'max_members': 20,
      'playback': <String, dynamic>{'position': 12.5, 'playing': true, 'rate': 1.0},
      'members': members,
    };

Map<String, dynamic> _member(String id, String nick, {bool host = false}) =>
    <String, dynamic>{
      'id': id,
      'nickname': nick,
      'name': nick,
      'role': host ? 'host' : 'guest',
      'muted': false,
      'online': true,
    };

void main() {
  test('房主发 approve：type/id/rid 齐全，seq 不填（服务端编号）', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    c.send(<String, dynamic>{'type': 'approve', 'id': 'm_guest1', 'rid': 'ap-1'});
    final Map<String, dynamic> f =
        jsonDecode(made.single.sent.last) as Map<String, dynamic>;
    expect(f['type'], 'approve');
    expect(f['id'], 'm_guest1');
    expect(f['rid'], 'ap-1');
    expect(f.containsKey('seq'), isFalse);
    await c.dispose();
  });

  test('房主发 reject：type/id/rid 齐全', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    c.send(<String, dynamic>{'type': 'reject', 'id': 'm_guest2', 'rid': 'rj-1'});
    final Map<String, dynamic> f =
        jsonDecode(made.single.sent.last) as Map<String, dynamic>;
    expect(f['type'], 'reject');
    expect(f['id'], 'm_guest2');
    expect(f['rid'], 'rj-1');
    await c.dispose();
  });

  test('joined 帧带 room：快照成员从 1 变 2（批准后进广播集合）', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    final _FakeTransport t = made.single;
    t.push(<String, dynamic>{
      'type': 'hello',
      'memberId': 'm_host',
      'memberToken': 'tk',
      'room': _room(<Map<String, dynamic>>[_member('m_host', '房主', host: true)]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.snapshot.value!.members.length, 1);

    t.push(<String, dynamic>{
      'type': 'joined',
      'seq': 2,
      'room': _room(<Map<String, dynamic>>[
        _member('m_host', '房主', host: true),
        _member('m_guest1', '客人1'),
      ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.snapshot.value!.members.length, 2);
    expect(c.snapshot.value!.members.last.id, 'm_guest1');
    await c.dispose();
  });

  test('members 帧带 room：被拒绝的人从快照里消失', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    final _FakeTransport t = made.single;
    t.push(<String, dynamic>{
      'type': 'hello',
      'memberId': 'm_host',
      'memberToken': 'tk',
      'room': _room(<Map<String, dynamic>>[
        _member('m_host', '房主', host: true),
        _member('m_guest2', '客人2'),
      ]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.snapshot.value!.members.length, 2);

    t.push(<String, dynamic>{
      'type': 'members',
      'seq': 3,
      'room': _room(<Map<String, dynamic>>[_member('m_host', '房主', host: true)]),
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.snapshot.value!.members.length, 1);
    expect(
      c.snapshot.value!.members.any((RoomMember m) => m.id == 'm_guest2'),
      isFalse,
    );
    await c.dispose();
  });

  test('error{code:not_host, rid} 原样透传，不崩不断线', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    final List<Map<String, dynamic>> seen = <Map<String, dynamic>>[];
    c.frames.listen(seen.add);
    made.single.push(<String, dynamic>{
      'type': 'error',
      'rid': 'ap-9',
      'code': 'not_host',
      'message': '只有房主能审批',
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen.length, 1);
    expect(seen.single['type'], 'error');
    expect(seen.single['code'], 'not_host');
    expect(seen.single['rid'], 'ap-9');
    expect(c.state, isNot(RoomClientState.closed));
    await c.dispose();
  });

  test('4004 房间满：转 closed 且不重连', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    await made.single.drop(4004);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(made.length, 1);
    expect(c.state, RoomClientState.closed);
    await c.dispose();
  });
}
