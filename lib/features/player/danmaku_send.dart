import '../../domain/entities/room_message.dart';
import '../../platform/room/room_snapshot.dart';

/// 发弹幕用的纯函数：把「用户在 X 秒按下发送」翻成房间协议的 danmaku 帧。
///
/// 为什么单独抽出来：
/// - pos 必须是**按下那一刻的播放位置**。服务端 `state.position` 是每 2 秒上报一次
///   的旧值，拿它会让弹幕滞后几十秒（M8 实踩）；录制时的时间更不行。
///   强制由调用方传 `Duration`，「谁的时间」变得不可搞错，也就能单测。
/// - 帧字段（type/text/pos/color/size/mode）与 11 号 §danmaku 一致，
///   服务端已在 SEQ_FRAMES 里，relay 照常转发，客户端不用改协议。
/// 「我是不是被禁言了」。
///
/// 抽成独立函数是为了能被单测钉死：被禁言时**一条帧都不发**
/// （chat 和 danmaku 都不发），也不做本地回显 —— 否则会出现
/// 「自己看得见、别人看不见」这种比发不出去更困惑的状态。
///
/// 拿不到快照 / 还不知道自己的 memberId 时返回 false（放行让服务端裁定），
/// 不能因为本地状态不全就把人静音。
bool amMuted(RoomSnapshot? snapshot, String? myMemberId) {
  if (snapshot == null || myMemberId == null || myMemberId.isEmpty) return false;
  return snapshot.memberById(myMemberId)?.muted ?? false;
}

Map<String, dynamic> buildDanmakuFrame({
  required String id,
  required String text,
  required Duration position,
  int color = 0xFFFFFF,
  double size = 1.0,
  String mode = 'scroll',
}) {
  return <String, dynamic>{
    'type': 'danmaku',
    // I-46：id 由客户端生成，本地回显与 WS 回来的同一条用同一个 id，
    // 否则「自己发的那条」会被算成两条弹幕。
    'id': id,
    'text': text,
    // 秒（double，保留毫秒精度）——服务端按 pos 排进时间轴
    'pos': position.inMilliseconds / 1000.0,
    'color': color,
    'size': size,
    'mode': mode,
  };
}

/// 本地回显用的 RoomDanmaku：服务端 relay 跳过发送者，不回显自己就看不到。
///
/// 与 [buildDanmakuFrame] 用同一个 [position]，保证「自己看到的」和
/// 「别人收到的」在同一条时间轴上。
RoomDanmaku buildLocalEchoDanmaku({
  required String text,
  required Duration position,
  required String id,
  required String from,
  String name = '我',
  int color = 0xFFFFFF,
  double size = 1.0,
  String mode = 'scroll',
  int? at,
}) {
  return RoomDanmaku(
    id: id,
    from: from,
    name: name,
    text: text,
    pos: position.inMilliseconds / 1000.0,
    at: at ?? DateTime.now().millisecondsSinceEpoch,
    color: color,
    mode: mode,
    size: size,
  );
}
