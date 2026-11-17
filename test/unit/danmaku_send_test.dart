import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yiqikan/features/player/danmaku_overlay.dart';
import 'package:yiqikan/features/player/danmaku_send.dart';
import 'package:yiqikan/platform/room/room_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('发弹幕开关（DanmakuSettings.sendEnabled）', () {
    test('默认开启；copyWith 关掉后保持；load/save 能落盘恢复', () async {
      // 默认值：第一次装 App 的人应该直接能发弹幕
      const DanmakuSettings def = DanmakuSettings();
      expect(def.sendEnabled, isTrue);
      // 与「看不看得到弹幕层」是两个字段，别被 copyWith 串了
      expect(def.visible, isTrue);

      final DanmakuSettings off = def.copyWith(sendEnabled: false);
      expect(off.sendEnabled, isFalse);
      expect(off.visible, isTrue, reason: '关发送不该顺手把弹幕层关掉');
      expect(off.speed, 120);
      expect(off.fontSize, 15);

      // 落盘 → 新实例读回来（模拟杀进程重启）
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await off.save();
      final DanmakuSettings loaded = await DanmakuSettings.load();
      expect(loaded.sendEnabled, isFalse);
      expect(loaded.visible, isTrue);

      // 再开回来
      await off.copyWith(sendEnabled: true).save();
      expect((await DanmakuSettings.load()).sendEnabled, isTrue);
    });
  });

  group('弹幕帧的 pos 取当前播放位置', () {
    test('pos = 传入 Duration 的秒；帧字段与 11 号 §danmaku 一致', () {
      final Map<String, dynamic> f = buildDanmakuFrame(
        id: 'dm_1',
        text: '调试弹幕 1',
        position: const Duration(milliseconds: 187340), // 187.34 秒
      );
      expect(f['type'], 'danmaku');
      expect(f['id'], 'dm_1');
      expect(f['text'], '调试弹幕 1');
      // 精确到毫秒，不是整秒、不是服务端 state.position
      expect(f['pos'], closeTo(187.34, 1e-9));
      expect(f['color'], 0xFFFFFF);
      expect(f['size'], 1.0);
      expect(f['mode'], 'scroll');

      // 同一位置：本地回显与上行帧必须落在同一条时间轴上
      final dynamic echo = buildLocalEchoDanmaku(
        text: '调试弹幕 1',
        position: const Duration(milliseconds: 187340),
        id: 'dm_1',
        from: 'm_1',
      );
      expect(echo.pos, f['pos']);
      expect(echo.text, f['text']);
      // I-46：回显 id 与上行帧 id 一致，才不会被当成两条
      expect(echo.id, f['id']);
      expect(echo.color, 0xFFFFFF);
    });
  });

  group('禁言拦截（amMuted）', () {
    RoomSnapshot snap({required bool muted, String extraRole = 'guest'}) {
      return RoomSnapshot(
        code: '123456',
        name: '一起看',
        hostId: 'm_host',
        approval: false,
        controlMode: 'host',
        mediaUrl: '',
        mediaTitle: '',
        mediaDuration: 600,
        epIndex: 0,
        playing: true,
        position: 0,
        rate: 1,
        updatedAt: 0,
        seq: 1,
        onlineCount: 2,
        members: <RoomMember>[
          const RoomMember(
            id: 'm_host',
            nickname: '房主',
            role: 'host',
            muted: false,
            online: true,
          ),
          RoomMember(
            id: 'm_guest',
            nickname: '我',
            role: extraRole,
            muted: muted,
            online: true,
          ),
        ],
      );
    }

    test('自己被禁言 → true；没被禁言 / 快照缺失 / id 为空 → false', () {
      // 核心用例：被禁言时 _sendChat 直接 return，chat 和 danmaku 一条帧都不发
      expect(amMuted(snap(muted: true), 'm_guest'), isTrue);
      // 禁的是别人，不该把我也挡住
      expect(amMuted(snap(muted: false), 'm_guest'), isFalse);
      expect(amMuted(snap(muted: true), 'm_host'), isFalse);
      // 本地状态不全时放行，交给服务端裁定，不能静默吞掉用户的话
      expect(amMuted(null, 'm_guest'), isFalse);
      expect(amMuted(snap(muted: true), null), isFalse);
      expect(amMuted(snap(muted: true), ''), isFalse);
    });
  });
}
