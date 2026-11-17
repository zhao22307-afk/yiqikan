/// 进房链接/二维码文本的纯解析（无 Flutter、无 IO，单测直接打）。
///
/// 认三种深链：
///   yiqikan://room/{code}            （App scheme；可以带 ?pwd=）
///   yiqikan://join?code={code}&addr=…（分享落地页那个按钮发的；addr 是房主地址）
///   https://{host}/r/{code}          （分享出去的网页短链；也可以带 ?pwd=）
/// 扫码时还额外接受「二维码里就是一串房间码」这种最常见的形式。
///
/// 解析不出来就返回 null —— 调用方静默丢弃（从桌面点错链接不该弹窗）。
library;

/// 房间码字符集：服务端 `Store.randId` 是 base36 大写，长度约定 6；
/// 这里放宽到 4..12，给以后换位数留余量，同时挡住中文、空白、URL 残渣。
final RegExp _codeRe = RegExp(r'^[A-Za-z0-9]{4,12}$');

/// 解析出来的一条进房链接。
class RoomLink {
  const RoomLink({
    required this.code,
    this.pwd = '',
    this.addr = '',
    this.raw = '',
  });

  /// 规范化的房间码（大写）。
  final String code;

  /// `?pwd=` 原文；没有就是空串。
  final String pwd;

  /// `?addr=` 里的房主地址（分享链接带过来的），没有就是空串。
  /// 有值时进房直接用它，跳过通道探测。
  final String addr;

  /// 原始文本，只用于日志。
  final String raw;

  @override
  String toString() => 'RoomLink(code=$code, pwd=${pwd.isEmpty ? '(none)' : '***'},'
      ' addr=${addr.isEmpty ? '(none)' : addr})';
}

/// 只认严格深链形式；不是深链（包括裸房间码）返回 null。
RoomLink? parseRoomLink(String? raw) {
  if (raw == null) return null;
  final String s = raw.trim();
  if (s.isEmpty) return null;

  Uri u;
  try {
    u = Uri.parse(s);
  } catch (_) {
    return null;
  }
  if (!u.hasScheme) return null;

  final String scheme = u.scheme.toLowerCase();
  String? code;
  final String host = u.host.toLowerCase();
  if (scheme == 'yiqikan' && host == 'join') {
    // yiqikan://join?code=ABC123&addr=https%3A%2F%2F…
    // 落地页上的按钮就是这个形状（code 在 query 里，不在 path 里）。
    code = (u.queryParameters['code'] ?? u.queryParameters['room'] ?? '').trim();
    if (code.isEmpty) {
      final List<String> seg =
          u.pathSegments.where((String e) => e.isNotEmpty).toList();
      if (seg.isNotEmpty) code = seg.first;
    }
  } else if (scheme == 'yiqikan') {
    // yiqikan://room/ABC123 → host=room, path=/ABC123
    if (host != 'room') return null;
    final List<String> seg =
        u.pathSegments.where((String e) => e.isNotEmpty).toList();
    if (seg.isEmpty) return null;
    code = seg.first;
  } else if (scheme == 'http' || scheme == 'https') {
    // https://x/r/ABC123
    final List<String> seg =
        u.pathSegments.where((String e) => e.isNotEmpty).toList();
    if (seg.length < 2) return null;
    if (seg[0].toLowerCase() != 'r') return null;
    code = seg[1];
  } else {
    return null;
  }

  if (!_codeRe.hasMatch(code)) return null;
  final String pwd =
      u.queryParameters['pwd'] ?? u.queryParameters['password'] ?? '';
  String addr = (u.queryParameters['addr'] ?? '').trim();
  while (addr.endsWith('/')) {
    addr = addr.substring(0, addr.length - 1);
  }
  return RoomLink(code: code.toUpperCase(), pwd: pwd, addr: addr, raw: s);
}

/// 扫码用：先按深链解析，再退一步把「内容本身就是房间码」的情况收下。
RoomLink? parseScanText(String? raw) {
  final RoomLink? link = parseRoomLink(raw);
  if (link != null) return link;
  final String s = (raw ?? '').trim().toUpperCase();
  if (!_codeRe.hasMatch(s)) return null;
  return RoomLink(code: s, raw: raw ?? '');
}
