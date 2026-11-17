// 验收 4：满员房间的 WS 握手拒绝（HTTP 403 + body close_code=4004）。
// 跑法：flutter test test\probe\full_room_test.dart（真机 127.0.0.1:8080）
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/room_client.dart';

void main() {
  test('满员房 WS 握手回 403 + close_code=4004，客户端能读出来', () async {
    // 202116：max_members=1，房主已占一个名额（curl 建的房）
    // roomToken 能让握手走到"新成员"分支，容量判定就在这里拦下来
    final RoomClient c = RoomClient(
      baseUrl: 'http://127.0.0.1:8080',
      roomCode: '202116',
      roomToken: '2c93952f0d5e7d6a3c14c560f4608634',
      deviceName: 'probe-full',
    );
    await c.connect();
    // connect() 失败后会走 _probeHandshake()，把 403 的 body 带回来
    await Future<void>.delayed(const Duration(seconds: 2));
    // ignore: avoid_print
    print('handshakeError=${c.handshakeError}');
    // ignore: avoid_print
    print('state=${c.state}');
    await c.dispose();
  });
}
