import 'package:flutter/foundation.dart';

/// 某个成员自己的播放进度（progress 帧覆盖式更新，Map 只存一份）。
@immutable
class MemberProgress {
  const MemberProgress({required this.position, required this.playing});

  final Duration position;
  final bool playing;
}

/// 房间成员（快照里的一项）。
@immutable
class RoomMember {
  const RoomMember({
    required this.id,
    required this.nickname,
    required this.role,
    required this.muted,
    required this.online,
    this.isBot = false,
    this.progress =
        const MemberProgress(position: Duration.zero, playing: false),
  });

  final String id;
  final String nickname;

  /// `host` 或 `guest`
  final String role;
  final bool muted;
  final bool online;

  /// D28：服务端 `bot` 标记，纯显示用（名字后缀 🤖），不参与权限判断
  final bool isBot;

  /// 快照里带下来的本人进度（没有就是 0 / 暂停）
  final MemberProgress progress;

  /// 这条成员相对权威 state 落后多少（正值=落后，负值=领先）
  Duration? lagFrom(Duration? authoritative) {
    if (authoritative == null) return null;
    return authoritative - progress.position;
  }

  bool get isOwner => role == 'host';

  RoomMember copyWith({bool? muted, bool? online}) => RoomMember(
        id: id,
        nickname: nickname,
        role: role,
        muted: muted ?? this.muted,
        online: online ?? this.online,
        isBot: isBot,
        progress: progress,
      );

  static RoomMember fromJson(Map<String, dynamic> j) => RoomMember(
        id: (j['id'] as String?) ?? '',
        nickname: (j['nickname'] as String?) ?? '',
        // 服务端只发 host/guest；老 rooms.json 里的 owner/member 就地映射
        role: _normRole((j['role'] as String?) ?? ''),
        muted: j['muted'] == true,
        online: j['online'] == true,
        isBot: j['bot'] == true,
        progress: _progressOf(j['progress']),
      );

  static MemberProgress _progressOf(Object? raw) {
    if (raw is! Map) return const MemberProgress(position: Duration.zero, playing: false);
    return MemberProgress(
      position: Duration(
          milliseconds: (((raw['position'] as num?)?.toDouble() ?? 0) * 1000).round()),
      playing: raw['playing'] == true,
    );
  }

  static String _normRole(String raw) {
    if (raw == 'host' || raw == 'owner') return 'host';
    return 'guest';
  }
}

/// hello 帧里的服务端快照（11 号 §4.1）。
///
/// 客户端不自己拼状态：进房、重连、断线补帧都以这份为准。
@immutable
class RoomSnapshot {
  const RoomSnapshot({
    required this.code,
    required this.name,
    required this.hostId,
    required this.approval,
    required this.controlMode,
    required this.mediaUrl,
    required this.mediaTitle,
    required this.mediaDuration,
    required this.epIndex,
    required this.playing,
    required this.position,
    required this.rate,
    required this.updatedAt,
    required this.seq,
    required this.members,
    required this.onlineCount,
  });

  final String code;
  final String name;
  /// 房主 memberId（不是名字；名字在 members[].nickname）
  final String hostId;

  /// 需要审批才能进（`is_private`）
  final bool approval;

  /// 控制模式：'host'（房主权威，默认）/ 'free'（自由共控）
  final String controlMode;
  final String mediaUrl;
  final String mediaTitle;
  final double mediaDuration;
  final int epIndex;
  final bool playing;
  final double position;
  final double rate;
  final int updatedAt;

  /// 快照生成时的服务端 seq，客户端用它对齐 `lastSeq`
  final int seq;
  final List<RoomMember> members;
  final int onlineCount;

  int get memberCount => members.length;

  RoomMember? memberById(String id) {
    for (final RoomMember m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 禁言帧落地：只换那一条成员，其余字段原样带过去（快照仍是一份不可变投影）。
  /// 控制模式帧落地：换 controlMode，其余原样
  RoomSnapshot withControlMode(String mode) {
    return RoomSnapshot(
      code: code,
      name: name,
      hostId: hostId,
      approval: approval,
      controlMode: mode == 'free' ? 'free' : 'host',
      mediaUrl: mediaUrl,
      mediaTitle: mediaTitle,
      mediaDuration: mediaDuration,
      epIndex: epIndex,
      playing: playing,
      position: position,
      rate: rate,
      updatedAt: updatedAt,
      seq: seq,
      members: members,
      onlineCount: onlineCount,
    );
  }

  RoomSnapshot withMemberMuted(String memberId, bool muted) {
    return RoomSnapshot(
      code: code,
      name: name,
      hostId: hostId,
      approval: approval,
      controlMode: controlMode,
      mediaUrl: mediaUrl,
      mediaTitle: mediaTitle,
      mediaDuration: mediaDuration,
      epIndex: epIndex,
      playing: playing,
      position: position,
      rate: rate,
      updatedAt: updatedAt,
      seq: seq,
      members: <RoomMember>[
        for (final RoomMember m in members)
          m.id == memberId ? m.copyWith(muted: muted) : m,
      ],
      onlineCount: onlineCount,
    );
  }

  /// members 帧落地：服务端只发 `members[]`（外加可选的 `host`），其余字段沿用旧快照。
  /// 禁言广播、移交房主广播都走这里 —— 之前只认 `room` 是对象，房主/被禁言状态到不了 UI。
  RoomSnapshot withMembers(List<RoomMember> next, {String? hostId}) {
    return RoomSnapshot(
      code: code,
      name: name,
      hostId: (hostId == null || hostId.isEmpty) ? this.hostId : hostId,
      approval: approval,
      controlMode: controlMode,
      mediaUrl: mediaUrl,
      mediaTitle: mediaTitle,
      mediaDuration: mediaDuration,
      epIndex: epIndex,
      playing: playing,
      position: position,
      rate: rate,
      updatedAt: updatedAt,
      seq: seq,
      members: next,
      onlineCount: onlineCount,
    );
  }

  /// 从 hello 帧取快照；没有 `room` 字段返回 null（老服务端）。
  static RoomSnapshot? fromHello(Map<String, dynamic> hello) {
    final Object? raw = hello['room'];
    if (raw is! Map) return null;
    final Map<String, dynamic> r = Map<String, dynamic>.from(raw);
    // host 可能是 memberId 字符串（新）或 {id,name}（老）
    final Object? hostRaw = r['host'];
    final String hostIdRaw = hostRaw is String
        ? hostRaw
        : (hostRaw is Map ? ((hostRaw['id'] as String?) ?? '') : '');
    final Map<String, dynamic> media =
        Map<String, dynamic>.from((r['media'] as Map?) ?? const <String, dynamic>{});
    final Map<String, dynamic> state =
        Map<String, dynamic>.from((r['state'] as Map?) ?? const <String, dynamic>{});
    // 服务端 hello 里权威播放块叫 playback（GET /api/rooms/{code} 同样这个名字）。
    // 两条路径同源，但有的帧只带 playback 不带 state —— 谁有 position 就用谁，
    // 否则新客拿到 0 就会从 0 秒起播（Bug1）。
    final Map<String, dynamic> pb =
        Map<String, dynamic>.from((r['playback'] as Map?) ?? const <String, dynamic>{});
    final Map<String, dynamic> play = pb.containsKey('position') ? pb : state;
    final List<RoomMember> ms = <RoomMember>[];
    final Object? list = r['members'];
    if (list is List) {
      for (final Object? one in list) {
        if (one is Map) ms.add(RoomMember.fromJson(Map<String, dynamic>.from(one)));
      }
    }
    return RoomSnapshot(
      code: (r['code'] as String?) ?? '',
      name: (r['name'] as String?) ?? '',
      hostId: hostIdRaw,
      approval: r['approval'] == true,
      controlMode: (r['control_mode'] as String?) == 'free' ? 'free' : 'host',
      mediaUrl: (media['url'] as String?) ?? '',
      mediaTitle: (media['title'] as String?) ?? '',
      mediaDuration: (media['duration'] as num?)?.toDouble() ??
          (play['duration'] as num?)?.toDouble() ??
          0,
      epIndex: (media['epIndex'] as num?)?.toInt() ?? 0,
      playing: play['playing'] == true,
      position: (play['position'] as num?)?.toDouble() ?? 0,
      rate: (play['rate'] as num?)?.toDouble() ?? 1.0,
      updatedAt: (state['updatedAt'] as num?)?.toInt() ?? 0,
      seq: (state['seq'] as num?)?.toInt() ?? 0,
      members: ms,
      onlineCount: (hello['online'] as num?)?.toInt() ?? 0,
    );
  }
}

