import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/host_change.dart';
import 'package:yiqikan/platform/room/room_client.dart';
import 'package:yiqikan/platform/room/room_snapshot.dart';

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

  Map<String, dynamic> get lastSent =>
      jsonDecode(sent.last) as Map<String, dynamic>;
}

RoomClient _client(List<_FakeTransport> made) => RoomClient(
      baseUrl: 'http://127.0.0.1:18081',
      roomCode: '123456',
      roomToken: 'tk',
      deviceName: 'probe',
      transportFactory: (Uri uri) async {
        final _FakeTransport t = _FakeTransport(uri);
        made.add(t);
        return t;
      },
    );

Map<String, dynamic> _room({
  required String host,
  required List<Map<String, dynamic>> members,
}) =>
    <String, dynamic>{
      'code': '123456',
      'name': '测试房',
      'host': host,
      'members': members,
      'state': <String, dynamic>{'playing': false, 'position': 0},
      'media': <String, dynamic>{'url': '', 'title': ''},
    };

Map<String, dynamic> _member(String id, String name,
        {bool muted = false, String role = 'guest'}) =>
    <String, dynamic>{
      'id': id,
      'nickname': name,
      'role': role,
      'muted': muted,
      'online': true,
    };

/// 进房：connected 给 memberId，hello 给首帧快照
Future<void> _enter(RoomClient c, _FakeTransport t, String me) async {
  t.push(<String, dynamic>{'type': 'connected', 'memberId': me});
  t.push(<String, dynamic>{
    'type': 'hello',
    'room': _room(host: 'm_host', members: <Map<String, dynamic>>[
      _member('m_host', '房主', role: 'host'),
      _member(me, '我'),
    ]),
  });
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('hostChangeText', () {
    test('首帧不算变更（原本就是房主，不该弹「你成为了房主」）', () {
      expect(hostChangeText(before: null, after: 'm_me', me: 'm_me'), '');
      expect(hostChangeText(before: '', after: 'm_me', me: 'm_me'), '');
    });

    test('房主变成我 → 你成为了房主', () {
      expect(hostChangeText(before: 'm_other', after: 'm_me', me: 'm_me'),
          '你成为了房主');
    });

    test('我不再是房主 → 房主已移交', () {
      expect(hostChangeText(before: 'm_me', after: 'm_other', me: 'm_me'),
          '房主已移交');
    });

    test('别人之间换 / 没换 / 自己 id 未知 → 不提示', () {
      expect(hostChangeText(before: 'm_a', after: 'm_b', me: 'm_me'), '');
      expect(hostChangeText(before: 'm_a', after: 'm_a', me: 'm_me'), '');
      expect(hostChangeText(before: 'm_a', after: 'm_b', me: ''), '');
      expect(hostChangeText(before: 'm_a', after: '', me: 'm_me'), '');
    });
  });

  group('禁言帧落地', () {
    test('muted 帧只改那一条成员，其余成员原样', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_me');

      made.single.push(<String, dynamic>{
        'type': 'muted',
        'memberId': 'm_me',
        'muted': true,
        'by': 'm_host',
        'seq': 9,
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final RoomSnapshot? s = c.snapshot.value;
      expect(s, isNotNull);
      expect(s!.memberById('m_me')!.muted, isTrue);
      expect(s.memberById('m_host')!.muted, isFalse);
      expect(s.memberById('m_host')!.isOwner, isTrue);
      await c.dispose();
    });

    test('members 帧（禁言后服务端广播的那份）带着 muted 落地', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_me');

      made.single.push(<String, dynamic>{
        'type': 'members',
        'room': _room(host: 'm_host', members: <Map<String, dynamic>>[
          _member('m_host', '房主', role: 'host'),
          _member('m_me', '我', muted: true),
        ]),
        'seq': 10,
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.snapshot.value!.memberById('m_me')!.muted, isTrue);
      await c.dispose();
    });

    test('members 帧真实形状（room 是房间码字符串 + members 数组）也能落地', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_me');

      // 服务端 LocalServer 广播出来的就是这一份：room 是 code，不是对象
      made.single.push(<String, dynamic>{
        'type': 'members',
        'room': 'ROOM01',
        'members': <Map<String, dynamic>>[
          _member('m_host', '房主', role: 'host'),
          _member('m_me', '我', muted: true),
        ],
        'seq': 11,
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.snapshot.value!.members.length, 2);
      expect(c.snapshot.value!.memberById('m_me')!.muted, isTrue);
      // 其它字段不能被这次广播清空（房间码沿用 hello 那份，不从 members 帧里猜）
      expect(c.snapshot.value!.hostId, 'm_host');
      expect(c.snapshot.value!.code, isNotEmpty);
      await c.dispose();
    });

    test('members 帧带 host 字段 → 房主换了，我这边 hostNotice 有话说', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_me');

      made.single.push(<String, dynamic>{
        'type': 'members',
        'room': 'ROOM01',
        'host': 'm_me',
        'members': <Map<String, dynamic>>[
          _member('m_host', '房主', role: 'guest'),
          _member('m_me', '我', role: 'host'),
        ],
        'seq': 12,
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.snapshot.value!.hostId, 'm_me');
      expect(c.snapshot.value!.memberById('m_me')!.role, 'host');
      expect(c.hostNotice.value, '你成为了房主');
      await c.dispose();
    });

    test('setMuted 发帧并等服务端确认：muted 到了才 true', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_host');

      final Future<bool> pending = c.setMuted('m_guest', true);
      final Map<String, dynamic> f = made.single.lastSent;
      expect(f['type'], 'setMuted');
      expect(f['memberId'], 'm_guest');
      expect(f['muted'], isTrue);

      made.single.push(<String, dynamic>{
        'type': 'muted',
        'memberId': 'm_guest',
        'muted': true,
        'seq': 11,
      });
      expect(await pending, isTrue);
      await c.dispose();
    });

    test('setMuted 被服务端拒（error 帧）→ false，不装成功', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_me');

      final Future<bool> pending = c.setMuted('m_other', true);
      made.single.push(<String, dynamic>{
        'type': 'error',
        'code': 'not_host',
        'message': '只有房主能禁言',
      });
      expect(await pending, isFalse);
      await c.dispose();
    });

    test('自己发的话被拒（muted 错误帧）时不影响快照', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_me');

      final RoomSnapshot before = c.snapshot.value!;
      made.single.push(<String, dynamic>{
        'type': 'error',
        'code': 'muted',
        'message': '你被禁言了',
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.snapshot.value, same(before));
      await c.dispose();
    });
  });

  group('移交房主', () {
    test('收到新 host 的 members 帧 → 我成为房主，hostNotice 有话说', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();
      await _enter(c, made.single, 'm_me');

      made.single.push(<String, dynamic>{
        'type': 'members',
        'room': _room(host: 'm_me', members: <Map<String, dynamic>>[
          _member('m_me', '我', role: 'host'),
          _member('m_host', '原房主'),
        ]),
        'seq': 12,
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.snapshot.value!.hostId, 'm_me');
      expect(c.snapshot.value!.memberById('m_me')!.isOwner, isTrue);
      expect(c.snapshot.value!.memberById('m_host')!.isOwner, isFalse);
      expect(c.hostNotice.value, '你成为了房主');
      await c.dispose();
    });

    test('房主改成别人 → 控制条判据变 false，hostNotice 说「房主已移交」', () async {
      final List<_FakeTransport> made = <_FakeTransport>[];
      final RoomClient c = _client(made);
      await c.connect();

      // 一进来我就是房主
      made.single.push(<String, dynamic>{'type': 'connected', 'memberId': 'm_me'});
      made.single.push(<String, dynamic>{
        'type': 'hello',
        'room': _room(host: 'm_me', members: <Map<String, dynamic>>[
          _member('m_me', '我', role: 'host'),
          _member('m_guest', '客人'),
        ]),
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.snapshot.value!.memberById('m_me')!.isOwner, isTrue);

      made.single.push(<String, dynamic>{
        'type': 'members',
        'room': _room(host: 'm_guest', members: <Map<String, dynamic>>[
          _member('m_me', '我'),
          _member('m_guest', '客人', role: 'host'),
        ]),
        'seq': 13,
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(c.snapshot.value!.hostId, 'm_guest');
      expect(c.snapshot.value!.memberById('m_me')!.isOwner, isFalse);
      expect(c.hostNotice.value, '房主已移交');
      await c.dispose();
    });
  });
}
