/// D26 多通道选路：通道模型 + 评分 + 策略排序（纯逻辑，不碰网络，可单测）。
///
/// 评分口径按 15 §D26（不是 04 §6.3 的 base 表）：
///   score = 1000 - rttMs*2 + bandwidthBonus - failCount*200
/// 其中 bandwidthBonus = kbps >= 10000 ? 100 : 0。
/// 本轮没有测速来源，[Channel.kbps] 恒为 0，所以 bonus 恒不触发 —— 这是有意的，
/// 不要为了"看起来完整"编一个假带宽。
library;

/// 通道健康状态。unknown = 还没探测过；probing = 正在探测；alive/dead = 最近一次结果。
enum ChannelState { unknown, probing, alive, dead }

/// 选路策略（04 §6.2；E8 加了 ipv6Only 一档）。
enum ChannelMode { auto, lanOnly, forceTunnel, ipv6Only }

/// 一条可选通道。lan 项是 host+port，tunnel 项是 url，两种形状不同，按 [id] 分支解析。
class Channel {
  Channel({
    required this.id,
    required this.name,
    this.url,
    this.host,
    this.port = 0,
    this.state = ChannelState.unknown,
    this.rttMs = 0,
    this.kbps = 0,
    this.failCount = 0,
  });

  /// 'lan' | 'tunnel'
  final String id;
  final String name;

  /// tunnel 用；lan 为 null
  final String? url;

  /// lan 用；tunnel 为 null
  final String? host;
  final int port;

  ChannelState state;
  int rttMs;
  int kbps;
  int failCount;

  /// 可以直接拿去拼 `/health`、`/api/rooms` 的根地址。
  String get baseUrl => url ?? 'http://$host:$port';

  bool get isTunnel => id == 'tunnel';

  @override
  String toString() => 'Channel($id,$name,$baseUrl,$state,${rttMs}ms)';
}

/// 把服务端 `/api/rooms/{code}` 里的 `addrs`（或 E8 的 `ranked`）数组解析成通道列表。
///
/// 形状不认识/缺字段的项直接跳过（旧服务端没有 addrs，或字段改名），不抛异常。
/// E8 之后除 lan 外的层都只给 url（tunnel / ipv6 / upnp / mesh / relay / explicit），
/// 所以「有 url 就按 url 收，没有 url 才要 host+port」。
List<Channel> parseChannels(Object? raw) {
  final List<Channel> out = <Channel>[];
  if (raw is! List) return out;
  for (final Object? item in raw) {
    if (item is! Map) continue;
    final Object? idRaw = item['id'];
    final String id = idRaw is String && idRaw.isNotEmpty ? idRaw : 'lan';
    final Object? nameRaw = item['name'];
    final String name = nameRaw is String && nameRaw.isNotEmpty
        ? nameRaw
        : (id == 'tunnel' ? '隧道' : '局域网');
    if (id == 'tunnel') {
      final Object? u = item['url'];
      if (u is! String || u.isEmpty) continue;
      out.add(Channel(id: 'tunnel', name: name, url: u));
      continue;
    }
    final Object? u = item['url'];
    if (u is String && u.isNotEmpty && id != 'lan') {
      out.add(Channel(id: id, name: name, url: u));
      continue;
    }
    final Object? h = item['host'];
    if (h is! String || h.isEmpty) continue;
    final Object? p = item['port'];
    final int port = p is int ? p : (int.tryParse('${p ?? ''}') ?? 0);
    if (port <= 0) continue;
    out.add(Channel(id: id, name: name, host: h, port: port));
  }
  return out;
}

/// 评分：dead 通道沉底，未探测过的算 0（不许冒充高分），其余按 15 号公式。
int scoreChannel(Channel c) {
  if (c.state == ChannelState.dead) return -1 << 20;
  if (c.state == ChannelState.unknown) return 0;
  int s = 1000 - c.rttMs * 2;
  if (c.kbps >= 10000) s += 100;
  s -= c.failCount * 200;
  return s;
}

/// 按策略过滤 + 排序（分高的在前；同分时 lan 排 tunnel 前面，保证 AUTO 的固定顺序）。
///
/// E8：服务端给了 `primary`（六层优先级算出来的那条）就无条件排第一 ——
/// 服务端比客户端更清楚哪条现在真能通（隧道刚起来、UPnP 刚映射上）。
/// 没给 primary 才走原来的评分排序。
List<Channel> rankForMode(List<Channel> all, ChannelMode mode,
    {Channel? primary}) {
  final List<Channel> ranked = _rankByScore(all, mode);
  if (primary == null) return ranked;
  final List<Channel> out = <Channel>[primary];
  for (final Channel c in ranked) {
    if (c.baseUrl == primary.baseUrl) continue;
    out.add(c);
  }
  return out;
}

List<Channel> _rankByScore(List<Channel> all, ChannelMode mode) {
  final List<Channel> kept = <Channel>[];
  for (final Channel c in all) {
    switch (mode) {
      case ChannelMode.auto:
        kept.add(c);
      case ChannelMode.lanOnly:
        if (!c.isTunnel) kept.add(c);
      case ChannelMode.forceTunnel:
        if (c.isTunnel) kept.add(c);
      case ChannelMode.ipv6Only:
        if (c.id == 'ipv6') kept.add(c);
    }
  }
  kept.sort((Channel a, Channel b) {
    final int byScore = scoreChannel(b).compareTo(scoreChannel(a));
    if (byScore != 0) return byScore;
    return (a.isTunnel ? 1 : 0).compareTo(b.isTunnel ? 1 : 0);
  });
  return kept;
}

/// 清晰度建议（15 号三档）：rtt<20 且带宽>20Mbps → 4K；rtt<50 → 1080P；否则 720P。
String suggestQuality(Channel c) {
  if (c.rttMs < 20 && c.kbps > 20000) return '4K';
  if (c.rttMs < 50) return '1080P';
  return '720P';
}

/// pref 里的字符串 → 枚举；不认识的一律按 auto。
ChannelMode channelModeFromPref(String? raw) {
  switch (raw) {
    case 'lanOnly':
      return ChannelMode.lanOnly;
    case 'forceTunnel':
      return ChannelMode.forceTunnel;
    case 'ipv6Only':
      return ChannelMode.ipv6Only;
    default:
      return ChannelMode.auto;
  }
}

String channelModeToPref(ChannelMode m) => m.name;

/// 给日志/UI 用的中文名。
String channelModeLabel(ChannelMode m) {
  switch (m) {
    case ChannelMode.lanOnly:
      return '仅局域网';
    case ChannelMode.forceTunnel:
      return '仅隧道';
    case ChannelMode.ipv6Only:
      return '仅 IPv6';
    case ChannelMode.auto:
      return '自动（优先局域网）';
  }
}
