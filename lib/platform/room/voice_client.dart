/// 语音信令的纯数据层（M8 7a：只有成员与状态，一行 WebRTC 都没有）。
///
/// 为什么单独放一个文件：解析逻辑要能在单测里直接调，不能依赖 RoomClient
/// （它一 new 就要 transport、要 SharedPreferences、要定时器，单测里起不来）。
/// 音频通路是 7b 的事，这里只负责把 `voice-state` 帧变成 UI 能画的东西。
library;

/// 语音房人数上限。服务端 `VOICE_MAX` 是权威，这里是客户端提前拦一道，
/// 免得用户点了按钮等一个必定失败的往返。
const int kVoiceMax = 4;

/// 一个在语音里的成员。`speaking` 本轮服务端恒为 false（7a 不做音量检测），
/// 但字段先留着，7b 打开上行时不用再改结构。
class VoiceMember {
  const VoiceMember({
    required this.id,
    required this.name,
    this.muted = false,
    this.speaking = false,
  });

  final String id;
  final String name;
  final bool muted;
  final bool speaking;

  factory VoiceMember.fromJson(Map<String, dynamic> j) => VoiceMember(
        id: (j['id'] as String?) ?? '',
        // 服务端两个历史字段名都出现过（name / nickname），按顺序兜
        name: (j['name'] as String?) ?? (j['nickname'] as String?) ?? '',
        muted: j['muted'] == true,
        speaking: j['speaking'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is VoiceMember &&
      other.id == id &&
      other.name == name &&
      other.muted == muted &&
      other.speaking == speaking;

  @override
  int get hashCode => Object.hash(id, name, muted, speaking);

  @override
  String toString() => 'VoiceMember($id,$name,muted=$muted,speaking=$speaking)';
}

/// 语音成员全量 + 两个瞬时标记。
/// `joined` = 我在不在这个列表里（由 [parseVoiceState] 用 memberId 算出来）；
/// `full` = 上一次 join 被 `voice-full` 拒了，UI 拿它把按钮置灰。
class VoiceState {
  const VoiceState({
    this.items = const <VoiceMember>[],
    this.joined = false,
    this.full = false,
  });

  static const VoiceState empty = VoiceState();

  final List<VoiceMember> items;
  final bool joined;
  final bool full;

  int get length => items.length;

  /// 给成员条画 🎤 用：一次拿全集，避免每个 chip 各扫一遍。
  Set<String> get ids => <String>{for (final VoiceMember m in items) m.id};

  bool has(String id) => id.isNotEmpty && items.any((VoiceMember m) => m.id == id);

  VoiceState copyWith({
    List<VoiceMember>? items,
    bool? joined,
    bool? full,
  }) =>
      VoiceState(
        items: items ?? this.items,
        joined: joined ?? this.joined,
        full: full ?? this.full,
      );

  @override
  bool operator ==(Object other) =>
      other is VoiceState &&
      other.joined == joined &&
      other.full == full &&
      other.items.length == items.length &&
      // 元素逐个比：List 的 == 是引用比较，直接比会永远判不等
      _sameItems(other.items);

  bool _sameItems(List<VoiceMember> other) {
    for (int i = 0; i < items.length; i++) {
      if (items[i] != other[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(items), joined, full);

  @override
  String toString() =>
      'VoiceState(n=$length,joined=$joined,full=$full,ids=${items.map((VoiceMember m) => m.id).join(",")})';
}

/// `voice-state` 帧 → [VoiceState]。
///
/// 只做三件事：丢掉不是 Map 的条目、丢掉 id 为空的条目、多余字段忽略。
/// 跳号 / 乱序由 RoomClient 的 seq 逻辑处理，这里不做顺序判断。
VoiceState parseVoiceState(Map<String, dynamic> j, {String me = ''}) {
  final Object? raw = j['items'];
  final List<VoiceMember> out = <VoiceMember>[];
  if (raw is List) {
    for (final Object? one in raw) {
      if (one is! Map) continue;
      final VoiceMember m = VoiceMember.fromJson(Map<String, dynamic>.from(one));
      if (m.id.isEmpty) continue; // 没 id 的条目 UI 上没法点、也没法比，直接丢
      out.add(m);
    }
  }
  return VoiceState(
    items: out,
    joined: me.isNotEmpty && out.any((VoiceMember m) => m.id == me),
  );
}
