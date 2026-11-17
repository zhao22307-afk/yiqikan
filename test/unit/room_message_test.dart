import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/entities/room_message.dart';
import 'package:yiqikan/platform/room/room_client.dart';

/// E 项数据通道：六帧进 notifier、环形缓冲上限、撤回、点赞、重连保留。
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
      roomCode: '111222',
      roomToken: 'tk',
      deviceName: 'probe',
      transportFactory: (Uri uri) async {
        final _FakeTransport t = _FakeTransport(uri);
        made.add(t);
        return t;
      },
    );

Map<String, dynamic> _chat(String id, String text) => <String, dynamic>{
      'type': 'chat',
      'id': id,
      'from': 'm_guest',
      'name': '客人',
      'kind': 'text',
      'text': text,
      'at': 1762339200123,
    };

void main() {
  test('chat 帧进 chats：字段完整（id/from/name/text/at）', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.single.push(_chat('ch_abc', '这段真好看'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final List<ChatMessage> list = c.chats.value;
    expect(list.length, 1);
    expect(list.single.id, 'ch_abc');
    expect(list.single.from, 'm_guest');
    expect(list.single.name, '客人');
    expect(list.single.text, '这段真好看');
    expect(list.single.at, 1762339200123);
    expect(list.single.isText, isTrue);
    await c.dispose();
  });

  test('chat-recall 删掉对应一条；找不到就忽略', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.single.push(_chat('ch_1', 'a'));
    made.single.push(_chat('ch_2', 'b'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.chats.value.length, 2);

    made.single.push(<String, dynamic>{'type': 'chat-recall', 'id': 'ch_1', 'seq': 999});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.chats.value.length, 1);
    expect(c.chats.value.single.id, 'ch_2');

    made.single.push(<String, dynamic>{'type': 'chat-recall', 'id': 'ch_404', 'seq': 1000});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.chats.value.length, 1);
    await c.dispose();
  });

  test('danmaku 帧进 danmakus：pos/color/mode/size/bold 都在', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.single.push(<String, dynamic>{
      'type': 'danmaku',
      'id': 'dm_abc123',
      'from': 'm_host',
      'name': '房主',
      'text': '前方高能',
      'pos': 1234.5,
      'color': 16777215,
      'mode': 'scroll',
      'size': 1.2,
      'bold': true,
      'at': 1762339200123,
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final RoomDanmaku d = c.danmakus.value.single;
    expect(d.id, 'dm_abc123');
    expect(d.text, '前方高能');
    expect(d.pos, 1234.5);
    expect(d.color, 16777215);
    expect(d.mode, 'scroll');
    expect(d.size, 1.2);
    expect(d.bold, isTrue);
    await c.dispose();
  });

  test('danmaku-like 只当通知不自增、danmaku-likes 以服务端计数为准', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    // 服务端顺序是「先 danmaku-likes{items}，再 relay danmaku-like」，
    // 所以接收端在 danmaku-like 上再 +1 会让所有非发送者永远多 1。
    made.single.push(<String, dynamic>{'type': 'danmaku-likes', 'items': <String, dynamic>{'dm_1': 1}, 'seq': 899});
    made.single.push(<String, dynamic>{'type': 'danmaku-like', 'id': 'dm_1'});
    made.single.push(<String, dynamic>{'type': 'danmaku-like', 'id': 'dm_1', 'seq': 900});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.danmakuLikes.value['dm_1'], 1);
    made.single.push(<String, dynamic>{'type': 'danmaku-likes', 'id': 'dm_1', 'n': 42, 'seq': 901});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.danmakuLikes.value['dm_1'], 42);
    await c.dispose();
  });

  test('reaction 进 reactions，最多 100 条', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    for (int i = 0; i < 130; i++) {
      made.single.push(<String, dynamic>{'type': 'reaction', 'emoji': '😂', 'at': i, 'id': 'm_$i'});
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.reactions.value.length, 100);
    expect(c.reactions.value.last.at, 129);
    await c.dispose();
  });

  test('连发 250 条 chat：只留最新 200 条且顺序正确', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    for (int i = 0; i < 250; i++) {
      made.single.push(_chat('ch_$i', 'm$i'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final List<ChatMessage> list = c.chats.value;
    expect(list.length, 200);
    expect(list.first.text, 'm50');
    expect(list.last.text, 'm249');
    for (int i = 1; i < list.length; i++) {
      expect(list[i].text, 'm${50 + i}');
    }
    await c.dispose();
  });

  test('连发 520 条 danmaku：只留最新 500 条且顺序正确', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    for (int i = 0; i < 520; i++) {
      made.single.push(<String, dynamic>{
        'type': 'danmaku',
        'id': 'dm_$i',
        'text': 'd$i',
        'pos': i.toDouble(),
        'from': 'm_host',
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final List<RoomDanmaku> list = c.danmakus.value;
    expect(list.length, 500);
    expect(list.first.text, 'd20');
    expect(list.last.text, 'd519');
    await c.dispose();
  });

  test('首次 hello 清空历史，重连 hello 保留', () async {
    final List<_FakeTransport> made = <_FakeTransport>[];
    final RoomClient c = _client(made);
    await c.connect();
    made.single.push(<String, dynamic>{'type': 'hello', 'memberId': 'm_a', 'resumeFrom': 0});
    made.single.push(_chat('ch_1', 'before'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.chats.value.length, 1);
    expect(c.joinedOnce, isTrue);

    await made.single.drop(1006);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(made.length, 2);
    made[1].push(<String, dynamic>{'type': 'connected', 'memberId': 'm_a'});
    made[1].push(<String, dynamic>{'type': 'hello', 'memberId': 'm_a', 'resumeFrom': 6});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.chats.value.length, 1);
    expect(c.chats.value.single.text, 'before');
    await c.dispose();
  });
}
