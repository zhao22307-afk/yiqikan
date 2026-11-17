// E 项验收探针：六帧中继 + 客户端数据通道（真机 127.0.0.1:8080，经 adb forward）
//
// 跑法：flutter test test\probe\e2e_frames_test.dart
// 前提：真机 App 已启动（adb forward tcp:8080 tcp:8080）
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/entities/room_message.dart';
import 'package:yiqikan/platform/room/room_client.dart';

const String base = 'http://127.0.0.1:8080';

Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
  final HttpClient c = HttpClient();
  final HttpClientRequest req = await c.postUrl(Uri.parse('$base$path'));
  req.headers.contentType = ContentType.json;
  final List<int> bytes = utf8.encode(jsonEncode(body));
  req.contentLength = bytes.length;
  req.add(bytes);
  final HttpClientResponse res = await req.close();
  final String txt = await res.transform(utf8.decoder).join();
  c.close();
  return jsonDecode(txt) as Map<String, dynamic>;
}

void say(String k, Object? v) => print('[$k] $v');

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('E: chat / chat-recall / danmaku / danmaku-like / reaction 六帧通道', () async {
    final Map<String, dynamic> created = await postJson('/api/rooms', <String, dynamic>{
      'name': 'E-probe',
      'video_url': 'http://127.0.0.1:9/probe.mp4',
      'approval': false,
      'owner_name': 'probe-host',
      'mode': 'lan',
      'max_members': 10,
    });
    final String code = created['code'] as String;
    final String roomToken = (created['room_token'] ?? '') as String;
    final String hostToken = (created['memberToken'] ?? '') as String;
    say('room', '$code roomToken=${roomToken.isNotEmpty} hostToken=${hostToken.isNotEmpty}');

    final RoomClient host = RoomClient(
      baseUrl: base,
      roomCode: code,
      roomToken: roomToken,
      deviceName: 'probe-host',
      memberToken: hostToken,
    );
    final RoomClient guest = RoomClient(
      baseUrl: base,
      roomCode: code,
      roomToken: roomToken,
      deviceName: 'probe-guest',
    );
    final List<String> hostErr = <String>[];
    final List<String> guestErr = <String>[];
    host.frames.listen((Map<String, dynamic> f) {
      if (f['type'] == 'error') hostErr.add(jsonEncode(f));
    });
    guest.frames.listen((Map<String, dynamic> f) {
      if (f['type'] == 'error') guestErr.add(jsonEncode(f));
    });

    await host.connect();
    await guest.connect();
    await wait(500);
    say('host.memberId', '${host.memberId} isHost=${host.snapshot.value?.hostId == host.memberId}');
    say('guest.memberId', '${guest.memberId}');
    say('host.chats.init', '${host.chats.value.length}');
    say('guest.chats.init', '${guest.chats.value.length}');

    // ---- 1) 房主发 chat -> 客人 chats ----
    host.send(<String, dynamic>{
      'type': 'chat',
      'kind': 'text',
      'text': '这段真好看',
      'frameId': 'fr_1',
    });
    await wait(400);
    final List<ChatMessage> gc = guest.chats.value;
    say('1.guest.chats.n', '${gc.length}');
    if (gc.isNotEmpty) {
      final ChatMessage m = gc.last;
      say('1.guest.chat.last',
          'id=${m.id} from=${m.from} name=${m.name} text=${m.text} at=${m.at} kind=${m.kind}');
    }
    expect(gc.length, 1);
    expect(gc.last.id.startsWith('ch_'), isTrue);
    expect(gc.last.from, host.memberId);
    expect(gc.last.name, isNotEmpty);
    expect(gc.last.text, '这段真好看');
    expect(gc.last.at, greaterThan(0));

    final String chatId = gc.last.id;

    // ---- 2) 客人发 danmaku -> 房主 danmakus ----
    guest.send(<String, dynamic>{
      'type': 'danmaku',
      'text': '前方高能',
      'pos': 12.5,
      'color': 16777215,
      'mode': 'scroll',
      'size': 1.0,
      'bold': false,
    });
    await wait(400);
    final List<RoomDanmaku> hd = host.danmakus.value;
    say('2.host.danmakus.n', '${hd.length}');
    if (hd.isNotEmpty) {
      final RoomDanmaku d = hd.last;
      say('2.host.danmaku.last',
          'id=${d.id} from=${d.from} name=${d.name} text=${d.text} pos=${d.pos} color=${d.color} mode=${d.mode}');
    }
    expect(hd.length, 1);
    expect(hd.last.id.startsWith('dm_'), isTrue);
    expect(hd.last.from, guest.memberId);
    expect(hd.last.text, '前方高能');
    expect(hd.last.pos, 12.5);
    final String danmakuId = hd.last.id;

    // ---- 2b) danmaku-like / danmaku-likes ----
    host.send(<String, dynamic>{'type': 'danmaku-like', 'id': danmakuId});
    await wait(250);
    host.send(<String, dynamic>{'type': 'danmaku-like', 'id': danmakuId});
    await wait(250);
    say('2b.guest.danmakuLikes', guest.danmakuLikes.value.toString());
    expect(guest.danmakuLikes.value[danmakuId], 2);
    host.send(<String, dynamic>{'type': 'danmaku-likes', 'id': danmakuId, 'n': 42});
    await wait(250);
    say('2b.guest.danmakuLikes.after', guest.danmakuLikes.value.toString());
    expect(guest.danmakuLikes.value[danmakuId], 42);

    // danmaku-like 缺 id -> 发的人收 errObj，别人不受影响
    final int guestChatsBeforeMissing = guest.chats.value.length;
    host.send(<String, dynamic>{'type': 'danmaku-like'});
    await wait(300);
    say('2c.host.err', hostErr.isEmpty ? '(none)' : hostErr.last);
    expect(hostErr.any((String s) => s.contains('missing_danmaku_id')), isTrue);
    expect(guest.chats.value.length, guestChatsBeforeMissing);

    // ---- 3) reaction ----
    guest.send(<String, dynamic>{'type': 'reaction', 'emoji': 'GOOD'});
    await wait(300);
    say('3.host.reactions',
        '${host.reactions.value.length} last=${host.reactions.value.isEmpty ? '-' : host.reactions.value.last}');
    expect(host.reactions.value.length, 1);
    expect(host.reactions.value.last.emoji, 'GOOD');
    expect(host.reactions.value.last.id, guest.memberId);

    // ---- 4) chat-recall ----
    host.send(<String, dynamic>{'type': 'chat-recall', 'id': chatId});
    await wait(400);
    say('4.guest.chats.afterRecall', '${guest.chats.value.length}');
    expect(guest.chats.value.where((ChatMessage m) => m.id == chatId).isEmpty, isTrue);

    host.send(<String, dynamic>{'type': 'chat-recall', 'id': 'ch_404'});
    await wait(250);
    say('4b.guest.chats.afterMiss',
        '${guest.chats.value.length} err=${guestErr.isEmpty ? "(none)" : guestErr.last}');
    expect(guestErr.isEmpty, isTrue);

    // ---- 5) 600 字 chat -> 服务端拒，其他人列表不变 ----
    final int guestChatsBefore = guest.chats.value.length;
    host.send(<String, dynamic>{'type': 'chat', 'kind': 'text', 'text': 'x' * 600});
    await wait(400);
    say('5.host.err', hostErr.isEmpty ? '(none)' : hostErr.last);
    say('5.guest.chats.n', '${guest.chats.value.length} (before=$guestChatsBefore)');
    expect(hostErr.any((String s) => s.contains('text_too_long')), isTrue);
    expect(guest.chats.value.length, guestChatsBefore);

    // 101 字 danmaku -> 同样拒；100 字整放行
    guest.send(<String, dynamic>{'type': 'danmaku', 'text': 'y' * 101, 'pos': 1.0});
    await wait(350);
    say('5b.guest.err', guestErr.isEmpty ? '(none)' : guestErr.last);
    expect(guestErr.any((String s) => s.contains('text_too_long')), isTrue);
    guest.send(<String, dynamic>{'type': 'danmaku', 'text': 'z' * 100, 'pos': 2.0});
    await wait(350);
    say('5c.host.danmakus.n', '${host.danmakus.value.length}');

    // ---- 6) 连发 250 条 chat -> 只留 200 条，顺序正确 ----
    for (int i = 0; i < 250; i++) {
      host.send(<String, dynamic>{'type': 'chat', 'kind': 'text', 'text': 'seq$i'});
    }
    await wait(2500);
    final List<ChatMessage> after = guest.chats.value;
    say('6.guest.chats.n', '${after.length}');
    say('6.first/last', '${after.isEmpty ? '-' : after.first.text} .. ${after.isEmpty ? '-' : after.last.text}');
    expect(after.length, 200);
    expect(after.last.text, 'seq249');
    bool ordered = true;
    for (int i = 1; i < after.length; i++) {
      final int a = int.parse(after[i - 1].text.substring(3));
      final int b = int.parse(after[i].text.substring(3));
      if (b != a + 1) ordered = false;
    }
    say('6.ordered', '$ordered');
    expect(ordered, isTrue);

    // ---- 7) 断线重连 -> 列表保留，seq 续传 ----
    final int beforeDrop = guest.chats.value.length;
    final int seqBefore = guest.lastSeq;
    say('7.before.drop', 'chats=$beforeDrop lastSeq=$seqBefore');
    await guest.debugDropConnection();
    await wait(1500);
    say('7.after.reconnect', 'chats=${guest.chats.value.length} lastSeq=${guest.lastSeq} '
        'state=${guest.state.name} memberId=${guest.memberId}');
    expect(guest.chats.value.length, beforeDrop);
    expect(guest.lastSeq, greaterThanOrEqualTo(seqBefore));

    // ---- 8) 首次进房 -> 历史为空 ----
    final Map<String, dynamic> created2 = await postJson('/api/rooms', <String, dynamic>{
      'name': 'E-probe-2',
      'video_url': 'http://127.0.0.1:9/probe2.mp4',
      'approval': false,
      'owner_name': 'probe-host',
      'mode': 'lan',
    });
    final RoomClient fresh = RoomClient(
      baseUrl: base,
      roomCode: created2['code'] as String,
      roomToken: (created2['room_token'] ?? '') as String,
      deviceName: 'probe-fresh',
    );
    await fresh.connect();
    await wait(400);
    say('8.fresh.joinedOnce',
        '${fresh.joinedOnce} chats=${fresh.chats.value.length} danmakus=${fresh.danmakus.value.length}');
    expect(fresh.joinedOnce, isTrue);
    expect(fresh.chats.value, isEmpty);
    await fresh.dispose();

    await guest.dispose();
    await host.dispose();
    say('done', 'E 项六帧通道全部校验通过');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
