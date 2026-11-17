/// 房间 Bot 的配置快照（D27，本地规则版，不接外部服务）。
///
/// 字段名以服务端 `LocalServer.handleBotConfig` 广播的 `bot-state` 为准：
/// `enabled / name / aliases / cooldownSec / hourlyQuota / occupySlot / memberId`。
/// 服务端**没有**下发 reply（它是配置入参，不是快照字段），所以 `reply`
/// 只在本机做默认值兜底，读到的永远是默认串——够用，不做持久化。
class BotState {
  const BotState({
    this.enabled = true,
    this.name = '小看',
    this.reply = '我在',
    this.memberId = '',
    this.aliases = const <String>[],
    this.cooldownSec = 10,
    this.hourlyQuota = 30,
    this.occupySlot = false,
  });

  final bool enabled;
  final String name;
  final String reply;
  final String memberId;
  final List<String> aliases;
  final int cooldownSec;
  final int hourlyQuota;
  final bool occupySlot;

  /// 关掉时的形态：配置页拿它当初始值也要有名字与默认值
  static BotState get off => const BotState(enabled: false);

  BotState copyWith({
    bool? enabled,
    String? name,
    String? reply,
    String? memberId,
    List<String>? aliases,
    int? cooldownSec,
    int? hourlyQuota,
    bool? occupySlot,
  }) {
    return BotState(
      enabled: enabled ?? this.enabled,
      name: name ?? this.name,
      reply: reply ?? this.reply,
      memberId: memberId ?? this.memberId,
      aliases: aliases ?? this.aliases,
      cooldownSec: cooldownSec ?? this.cooldownSec,
      hourlyQuota: hourlyQuota ?? this.hourlyQuota,
      occupySlot: occupySlot ?? this.occupySlot,
    );
  }

  @override
  String toString() =>
      'BotState(enabled=$enabled name=$name aliases=$aliases cd=$cooldownSec '
      'quota=$hourlyQuota slot=$occupySlot mid=$memberId)';
}

/// 把一帧 `bot-state` 解成 [BotState]；不是这个类型的帧返回 null。
///
/// 三条硬要求：只认 `type == 'bot-state'`、`aliases` 同时吃 List 与逗号串、
/// 任何缺字段都给默认值（不抛）。
BotState? parseBotState(Map<String, dynamic> j) {
  if (j['type'] != 'bot-state') return null;
  final Object? rawAliases = j['aliases'];
  final List<String> aliases = <String>[];
  if (rawAliases is List) {
    for (final Object? a in rawAliases) {
      final String t = (a ?? '').toString().trim();
      if (t.isNotEmpty) aliases.add(t);
    }
  } else if (rawAliases is String) {
    for (final String a in rawAliases.split(RegExp(r'[,，\n]'))) {
      final String t = a.trim();
      if (t.isNotEmpty) aliases.add(t);
    }
  }
  final String name = (j['name'] ?? '小看').toString();
  if (aliases.isEmpty) aliases.add(name);
  return BotState(
    enabled: j['enabled'] == false ? false : true,
    name: name,
    reply: (j['reply'] ?? '我在').toString(),
    memberId: (j['memberId'] ?? '').toString(),
    aliases: List<String>.unmodifiable(aliases),
    cooldownSec: _int(j['cooldownSec'], 10),
    hourlyQuota: _int(j['hourlyQuota'], 30),
    occupySlot: j['occupySlot'] == true,
  );
}

int _int(Object? v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}
