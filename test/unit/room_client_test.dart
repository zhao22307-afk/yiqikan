import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/room_client.dart';
import 'package:yiqikan/platform/room/room_snapshot.dart';

class _FakeTransport implements RoomTransport {
  _FakeTransport(this.uri);

  final Uri uri;
  final StreamController<String> ctrl = StreamController<String>();
  final List<String> sent = <String>[];
  int? _closeCode;
  bool closed = false;

  @override
  Stream<String> get messages => ctrl.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close([int code = 1000, String reason = '']) async {
    closed = true;
    _closeCode = code;
    await ctrl.close();
  }

  /// 模拟服务端推一帧。
  void push(Map<String, dynamic> j) => ctrl.add(jsonEncode(j));

  /// 模拟服务端断开（可带关闭码）。
  Future<void> drop([int? code]) async {
    _closeCode = code;
    await ctrl.close();
  }
}

RoomClient _client(List<_FakeTransport> made, {int maxQueue = 128}) => RoomClient(
      baseUrl: 'http://127.0.0.1:18081',
      roomCode: '123456',
      roomToken: 'tk',
      deviceName: 'probe',
      maxQueue: maxQueue,
      transportFactory: (Uri uri) async {
        final _FakeTransport t = _FakeTransport(uri);
        made.add(t);
        return t;
      },
    );

void main() {
  test('ws 地址由 http 换成 ws 并带 room/token', () async {
    final RoomClient c = _client(<_FakeTransport>[]);
    expect(c.wsUri.scheme, 'ws');
    expect(c.wsUri.path, '/ws');
    expect(c.wsUri.queryParameters['room'], '123456');
    expect(c.wsUri.queryParameters['token'], 'tk');
  });

  test('发送计数从 1 起单调递增，hello 带 lastSeq=0', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    c.send(<String, dynamic>{'type': 'control', 'action': 'pause'});
    c.send(<String, dynamic>{'type': 'chat', 'text': 'hi'});
    expect(made.single.sent.length, 3);
    final Map<String, dynamic> hello =
        jsonDecode(made.single.sent.first) as Map<String, dynamic>;
    expect(hello['type'], 'hello');
    expect(hello['lastSeq'], 0);
    expect((jsonDecode(made.single.sent[1]) as Map<String, dynamic>)['type'], 'control');
    await c.dispose();
  });

  test('过期 state 帧被丢弃，lastSeq 只增', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    final List<int> seen = <int>[];
    c.frames.listen((Map<String, dynamic> f) {
      if (f['seq'] is int) seen.add(f['seq'] as int);
    });
    final _FakeTransport t = made.single;
    t.push(<String, dynamic>{'type': 'state', 'seq': 3, 't': 10});
    t.push(<String, dynamic>{'type': 'state', 'seq': 3, 't': 99}); // 过期，丢
    t.push(<String, dynamic>{'type': 'state', 'seq': 5, 't': 12});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen, <int>[3, 5]);
    expect(c.lastSeq, 5);
    await c.dispose();
  });

  test('队列满时丢最老的非 critical 帧（背压）', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made, maxQueue: 8);
    // 不 connect：所有帧进队列
    for (int i = 0; i < 12; i++) {
      c.send(<String, dynamic>{'type': 'danmaku', 'i': i});
    }
    expect(c.queuedCount, 8);
    expect(c.droppedCount, 4);
    c.send(<String, dynamic>{'type': 'hello'}, critical: true);
    expect(c.queuedCount, 8); // critical 挤掉最老的，仍不超上限
    await c.dispose();
  });

  test('重连时 hello 带 lastSeq+1（续传起点）', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.single.push(<String, dynamic>{'type': 'state', 'seq': 7, 't': 1});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await made.single.drop(1006);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 重连退避 1s 后触发
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(made.length, 2);
    final Map<String, dynamic> hello =
        jsonDecode(made[1].sent.first) as Map<String, dynamic>;
    expect(hello['lastSeq'], 8);
    await c.dispose();
  });

  test('4005 被踢后不再重连', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    await made.single.drop(4005);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(made.length, 1);
    expect(c.state, RoomClientState.closed);
    await c.dispose();
  });
  test('seq 跳号时打 gap 并主动发 sync', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    final _FakeTransport t = made.single;
    t.push(<String, dynamic>{'type': 'state', 'seq': 1, 't': 0});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 服务端手动跳号（1 → 4）
    t.push(<String, dynamic>{'type': 'members', 'seq': 4});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.lastSeq, 4);
    final bool askedSync = t.sent.any((String s) {
      final Map<String, dynamic> j = jsonDecode(s) as Map<String, dynamic>;
      return j['type'] == 'sync';
    });
    expect(askedSync, isTrue);
    await c.dispose();
  });

  test('progress 不进队列：连发 20 条只留一条且 200ms 内合并', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    // 不 connect，沙盒里验证合并
    for (int i = 0; i < 20; i++) {
      c.send(<String, dynamic>{'type': 'progress', 'position': i});
    }
    expect(c.queuedCount, 0); // 一条都没进队列
    await c.connect(); // 触发 _flushCoalesced
    await Future<void>.delayed(const Duration(milliseconds: 260));
    final int progressCount = made.single.sent.where((String s) {
      final Map<String, dynamic> j = jsonDecode(s) as Map<String, dynamic>;
      return j['type'] == 'progress';
    }).length;
    expect(progressCount, 1);
    final Map<String, dynamic> last = (jsonDecode(made.single.sent.last) as Map<String, dynamic>);
    expect(last['position'], 19);
    await c.dispose();
  });

  test('队列打满时 critical 帧不丢，droppable 记 drop', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made, maxQueue: 4);
    c.send(<String, dynamic>{'type': 'hello'}); // critical
    for (int i = 0; i < 10; i++) {
      c.send(<String, dynamic>{'type': 'danmaku', 'i': i});
    }
    expect(c.queuedCount, 4);
    expect(c.droppedCount, greaterThan(0));
    await c.connect();
    final List<String> types = made.single.sent
        .map((String s) => (jsonDecode(s) as Map<String, dynamic>)['type'] as String)
        .toList();
    expect(types.first, 'hello');
    expect(types.where((String t) => t == 'hello').length, greaterThanOrEqualTo(1));
    await c.dispose();
  });

  test('hello 快照解析：members / state / media 都对', () async {
    final RoomClient c = _client(<_FakeTransport>[]);
    final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
      'type': 'hello',
      'online': 2,
      'room': <String, dynamic>{
        'code': '123456',
        'name': '周五电影夜',
        'host': 'm_1',
        'approval': true,
        'media': <String, dynamic>{'url': 'http://x/a.mp4', 'title': '测试片 1', 'duration': 600, 'epIndex': 2},
        'state': <String, dynamic>{'playing': true, 'position': 123.5, 'rate': 1.0, 'updatedAt': 1700000000, 'seq': 9},
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'm_1', 'nickname': '房主', 'role': 'host', 'muted': false, 'online': true},
          <String, dynamic>{'id': 'm_2', 'nickname': '阿伟', 'role': 'guest', 'muted': true, 'online': false},
        ],
      },
    });
    expect(s, isNotNull);
    expect(s!.memberCount, 2);
    expect(s.onlineCount, 2);
    expect(s.position, 123.5);
    expect(s.playing, isTrue);
    expect(s.mediaTitle, '测试片 1');
    expect(s.epIndex, 2);
    expect(s.hostId, 'm_1');
    expect(s.memberById('m_2')!.muted, isTrue);
    expect(s.memberById('m_2')!.isOwner, isFalse);
    expect(s.memberById('m_1')!.isOwner, isTrue);
    await c.dispose();
  });
  test('老数据 role owner/member 映射成 host/guest', () async {
    final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
      'room': <String, dynamic>{
        'code': '9',
        'host': 'm_old',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'm_old', 'nickname': '老房主', 'role': 'owner'},
          <String, dynamic>{'id': 'm_g', 'nickname': '客人', 'role': 'member'},
        ],
      },
    });
    expect(s!.memberById('m_old')!.role, 'host');
    expect(s.memberById('m_old')!.isOwner, isTrue);
    expect(s.memberById('m_g')!.role, 'guest');
    expect(s.memberById('m_g')!.isOwner, isFalse);
  });

  test('host 是 memberId 且非空', () async {
    final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
      'room': <String, dynamic>{
        'code': '9',
        'host': 'm_abc1234567',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'm_abc1234567', 'nickname': '房主', 'role': 'host', 'online': true},
        ],
      },
    });
    expect(s!.hostId, 'm_abc1234567');
    expect(s.hostId.isNotEmpty, isTrue);
    expect(s.memberById(s.hostId)!.nickname, '房主');
    expect(s.memberById(s.hostId)!.online, isTrue);
  });

  test('media.title 只取片名，不回落房间名', () async {
    final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
      'room': <String, dynamic>{
        'code': '9',
        'name': '周五电影夜',
        'host': 'm_1',
        'media': <String, dynamic>{'url': 'http://x/a.mp4', 'duration': 60},
      },
    });
    expect(s!.name, '周五电影夜');
    expect(s.mediaTitle, '');
  });
  test('wsUri 不带 member_token 时不污染 query', () {
    final RoomClient c = RoomClient(
      baseUrl: 'http://10.0.0.2:8080',
      roomCode: '4821',
      roomToken: 'room-secret',
      deviceName: '测试机',
    );
    final Uri u = c.wsUri;
    expect(u.queryParameters['room'], '4821');
    expect(u.queryParameters['token'], 'room-secret');
    expect(u.queryParameters.containsKey('member_token'), isFalse);
    expect(u.path, '/ws');
  });

  test('wsUri 带 member_token（房主复用身份的唯一通道）', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.first.push(<String, dynamic>{'type': 'hello', 'memberId': 'm_1', 'memberToken': 'mt-1', 'room': <String, dynamic>{}});
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(c.memberToken, 'mt-1');
    expect(c.wsUri.queryParameters['member_token'], 'mt-1');
    await c.dispose();
  });

  test('host 是老对象格式时也能取到 hostId', () {
    final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
      'room': <String, dynamic>{
        'code': '9',
        'host': <String, dynamic>{'id': 'm_legacy', 'name': '老房主'},
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'm_legacy', 'nickname': '老房主', 'role': 'owner'},
        ],
      },
    });
    expect(s!.hostId, 'm_legacy');
    expect(s.memberById(s.hostId)!.isOwner, isTrue);
  });
  test('progress 帧带 memberId，客户端只留一份 Map', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.first.push(<String, dynamic>{
      'type': 'progress',
      'memberId': 'm_1',
      'position': 500.0,
      'playing': true,
    });
    made.first.push(<String, dynamic>{
      'type': 'progress',
      'memberId': 'm_1',
      'position': 900.0,
      'playing': true,
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(c.progress.value.length, 1);
    expect(c.progress.value['m_1']!.position, const Duration(seconds: 900));
    await c.dispose();
  });

  test('state 帧更新权威位置并带 seq', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.first.push(<String, dynamic>{
      'type': 'state',
      'seq': 7,
      'state': <String, dynamic>{'position': 1234.0, 'playing': true, 'by': 'm_h'},
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(c.authoritative.value, const Duration(seconds: 1234));
    await c.dispose();
  });

  test('快照 members[].progress 解析', () {
    final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
      'room': <String, dynamic>{
        'code': '9',
        'host': 'm_h',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'm_h',
            'nickname': '房主',
            'role': 'host',
            'progress': <String, dynamic>{'position': 5000.0, 'playing': true},
          },
        ],
      },
    });
    expect(s!.memberById('m_h')!.progress.position, const Duration(seconds: 5000));
    expect(s.memberById('m_h')!.progress.playing, isTrue);
  });

  test('落后秒数由权威位置与本人进度算出', () {
    final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{
      'room': <String, dynamic>{
        'code': '9',
        'host': 'm_h',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'm_g',
            'nickname': '客人',
            'role': 'guest',
            'progress': <String, dynamic>{'position': 2000.0},
          },
        ],
      },
    });
    final Duration? lag =
        s!.memberById('m_g')!.lagFrom(const Duration(seconds: 2005));
    expect(lag, const Duration(seconds: 5));
  });

  test('state 帧按本地单调时钟外推（不看服务端时间戳）', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = RoomClient(
      baseUrl: 'http://127.0.0.1:8080',
      roomCode: 'r1',
      roomToken: 't1',
      deviceName: 'me',
      transportFactory: (Uri uri) async {
        final _FakeTransport t = _FakeTransport(uri);
        made.add(t);
        return t;
      },
    );
    await c.connect();
    made.single.push(<String, dynamic>{
      'type': 'state',
      'state': <String, dynamic>{
        'position': 100.0,
        'playing': true,
        'rate': 1.0,
        // 故意给一个离谱的服务端时间戳：新实现不许用它做差（跨设备时钟不同步）
        'updatedAt': 1,
      },
      'seq': 1,
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.expectedPosition?.inSeconds, 100);
    c.debugAdvanceAuthClock(const Duration(seconds: 5));
    expect(c.expectedPosition!.inSeconds, greaterThanOrEqualTo(104));
    await c.dispose();
  });

  test('state 暂停时不外推', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = RoomClient(
      baseUrl: 'http://127.0.0.1:8080',
      roomCode: 'r1',
      roomToken: 't1',
      deviceName: 'me',
      transportFactory: (Uri uri) async {
        final _FakeTransport t = _FakeTransport(uri);
        made.add(t);
        return t;
      },
    );
    await c.connect();
    made.single.push(<String, dynamic>{
      'type': 'state',
      'state': <String, dynamic>{
        'position': 42.0,
        'playing': false,
        'rate': 1.0,
      },
      'seq': 1,
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    c.debugAdvanceAuthClock(const Duration(seconds: 30));
    expect(c.expectedPosition?.inSeconds, 42);
    await c.dispose();
  });

  test('state 倍速 2x：外推按两倍走', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = RoomClient(
      baseUrl: 'http://127.0.0.1:8080',
      roomCode: 'r1',
      roomToken: 't1',
      deviceName: 'me',
      transportFactory: (Uri uri) async {
        final _FakeTransport t = _FakeTransport(uri);
        made.add(t);
        return t;
      },
    );
    await c.connect();
    made.single.push(<String, dynamic>{
      'type': 'state',
      'state': <String, dynamic>{
        'position': 0.0,
        'playing': true,
        'rate': 2.0,
      },
      'seq': 1,
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    c.debugAdvanceAuthClock(const Duration(seconds: 4));
    expect(c.expectedPosition!.inSeconds, greaterThanOrEqualTo(7));
    await c.dispose();
  });

  test('lagFrom 用外推后的位置算落后秒数', () async {
    final RoomSnapshot? snap = RoomSnapshot.fromHello(<String, dynamic>{
      'room': <String, dynamic>{
        'code': 'r1',
        'members': <dynamic>[
          <String, dynamic>{
            'id': 'm_1',
            'nickname': 'A',
            'role': 'host',
            'progress': <String, dynamic>{'position': 90.0, 'playing': true},
          },
        ],
      },
    });
    final Duration? lag =
        snap!.members.first.lagFrom(const Duration(seconds: 100));
    expect(lag, const Duration(seconds: 10));
  });}







