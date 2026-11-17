import 'package:flutter/foundation.dart';

/// 房间聊天的六帧数据通道（11 号 §7 / §8 的帧定义，客户端只做投影，不拼状态）。
///
/// 注意：`DanmakuItem`（lib/domain/entities/danmaku.dart）是「本地弹幕缓存」
/// 的载荷（t/m/c/p），和房间弹幕帧（id/pos/color/mode/size）不是一套字段，
/// 所以这里另立 `RoomDanmaku`，避免两个模型互相污染。
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.from,
    required this.name,
    required this.kind,
    required this.text,
    required this.at,
    this.url = '',
    this.width = 0,
    this.height = 0,
    this.duration = 0,
    this.frameId = '',
  });

  /// `ch_` + 8 位 base36；服务端没给就补
  final String id;

  /// 发送者的 memberId（服务端填，客户端传的不算数）
  final String from;

  /// 发送者昵称（服务端填）
  final String name;

  /// text / image / voice
  final String kind;

  final String text;

  /// 毫秒时间戳
  final int at;

  /// kind=image/voice 时的资源地址
  final String url;

  /// 图片宽高（kind=image）
  final int width;
  final int height;

  /// 语音秒数（kind=voice）
  final double duration;

  /// 发送时所在的片/集标识
  final String frameId;

  bool get isText => kind == 'text';
  bool get isImage => kind == 'image';
  bool get isVoice => kind == 'voice';

  static ChatMessage fromFrame(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] as String?) ?? '',
        from: (j['from'] as String?) ?? '',
        name: (j['name'] as String?) ?? (j['nickname'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? 'text',
        text: (j['text'] as String?) ?? '',
        at: (j['at'] as num?)?.toInt() ?? 0,
        url: (j['url'] as String?) ?? '',
        width: (j['w'] as num?)?.toInt() ?? 0,
        height: (j['h'] as num?)?.toInt() ?? 0,
        duration: (j['dur'] as num?)?.toDouble() ?? 0,
        frameId: (j['frameId'] as String?) ?? '',
      );

  @override
  String toString() => 'ChatMessage($id, $kind, from=$from, ${text.length} chars)';
}

/// 房间弹幕（11 号 §8.1）：`pos` 是相对视频的秒数，是唯一的时间基准。
@immutable
class RoomDanmaku {
  const RoomDanmaku({
    required this.id,
    required this.from,
    required this.name,
    required this.text,
    required this.pos,
    required this.at,
    this.color = 0xFFFFFF,
    this.mode = 'scroll',
    this.size = 1.0,
    this.bold = false,
    this.frameId = '',
  });

  final String id;
  final String from;
  final String name;
  final String text;

  /// 相对视频的秒数（不是墙钟）
  final double pos;

  /// 毫秒时间戳（发送时刻）
  final int at;

  /// RGB（帧里是十进制整数，如 16777215 = 0xFFFFFF = 白）。
  /// 不含 alpha，渲染层要自己补 0xFF。
  final int color;

  /// scroll / top / bottom
  final String mode;

  /// 0.8 / 1.0 / 1.2
  final double size;

  final bool bold;
  final String frameId;

  static RoomDanmaku fromFrame(Map<String, dynamic> j) => RoomDanmaku(
        id: (j['id'] as String?) ?? '',
        from: (j['from'] as String?) ?? '',
        name: (j['name'] as String?) ?? (j['nickname'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        pos: (j['pos'] as num?)?.toDouble() ?? 0,
        at: (j['at'] as num?)?.toInt() ?? 0,
        color: (j['color'] as num?)?.toInt() ?? 0xFFFFFF,
        mode: (j['mode'] as String?) ?? 'scroll',
        size: (j['size'] as num?)?.toDouble() ?? 1.0,
        bold: j['bold'] == true,
        frameId: (j['frameId'] as String?) ?? '',
      );

  @override
  String toString() => 'RoomDanmaku($id, pos=$pos, ${text.length} chars)';
}

/// 表情回应（11 号 §7.4）：id 是发送者 memberId。
@immutable
class ReactionItem {
  const ReactionItem({required this.emoji, required this.at, required this.id});

  final String emoji;
  final int at;

  /// 发送者 memberId
  final String id;

  static ReactionItem fromFrame(Map<String, dynamic> j) => ReactionItem(
        emoji: (j['emoji'] as String?) ?? '',
        at: (j['at'] as num?)?.toInt() ?? 0,
        id: (j['id'] as String?) ?? '',
      );

  @override
  String toString() => 'ReactionItem($emoji, from=$id)';
}
