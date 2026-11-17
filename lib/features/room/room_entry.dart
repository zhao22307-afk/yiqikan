import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/local/prefs.dart';
import '../../platform/room/channel.dart';
import '../../platform/room/lan_discovery.dart';
import '../../platform/room/room_client.dart';
import '../player/player_controller.dart';
import '../player/player_page.dart';

/// 建房结果：房间码 + 房主自己的身份（memberToken 用来复用 host 成员）。
class CreatedRoom {
  const CreatedRoom({
    required this.code,
    required this.roomToken,
    required this.ownerMemberId,
    required this.memberToken,
    required this.videoUrl,
    required this.title,
  });

  final String code;
  final String roomToken;
  final String ownerMemberId;
  final String memberToken;
  final String videoUrl;
  final String title;
}

/// 验收用的本地样本：运行时拼路径，绝不把 applicationId 后缀写进常量
/// （debug 是 top.yiqikan.app.debug，release 是 top.yiqikan.app，写死必挂）。
/// 样本不存在时返回 null，由调用方提示「先从片源里选片子」。
Future<String?> demoStreamUrl() async {
  final List<Directory> dirs = <Directory>[];
  try {
    // getFilesDir()（= files/，验收样本推在这里）与 Documents 两处都找
    dirs.add(Directory((await getApplicationSupportDirectory()).path));
    dirs.add(await getApplicationDocumentsDirectory());
  } catch (_) {
    return null;
  }
  for (final Directory dir in dirs) {
    for (final String name in const <String>['sample.mkv', 'sample.mp4']) {
      final File f = File('${dir.path}/$name');
      if (await f.exists()) return Uri.file(f.path).toString();
    }
  }
  return null;
}

/// 本地内置服务地址（真机走 127.0.0.1，服务由 App 自己起）。
const String kLocalServerBase = 'http://127.0.0.1:8080';

/// 解析后端地址：连接配置里填了「对方地址」就用它，否则用本机。
/// 客人连别人房间时必须是对方地址，否则 /join 打到自己身上（房间不存在）。
///
/// 这是原包 joinInfo() 六层优先级的第一层「显式配置」——
/// 服务端 /local/settings 早就把 peer 存下来了，客户端以前一次都没读过。
Future<String> resolveServerBase() async {
  final Dio d = Dio(BaseOptions(
    baseUrl: kLocalServerBase,
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 2),
  ));
  try {
    final Response<dynamic> r = await d.get<dynamic>('/local/settings?json=1');
    final Object? peer = (r.data is Map) ? (r.data as Map)['peer'] : null;
    if (peer is String && peer.trim().isNotEmpty) {
      String p = peer.trim();
      while (p.endsWith('/')) {
        p = p.substring(0, p.length - 1);
      }
      debugPrint('[YQK-JOIN] base=$p (peer)');
      return p;
    }
  } on Object catch (e) {
    debugPrint('[YQK-JOIN] peer lookup failed: $e');
  } finally {
    d.close(force: true);
  }
  return kLocalServerBase;
}

/// E8：一次取回「所有通道 + 服务端算出的 primary」。
///
/// primary 是服务端按六层优先级挑出来的那条（explicit → tunnel → upnp →
/// ipv6 → mesh → lan），客户端拿它直接排第一，别再自己猜。
class ChannelFetch {
  ChannelFetch(this.all, this.primary, this.rankedIds);

  final List<Channel> all;
  final Channel? primary;
  final List<String> rankedIds;

  bool get isEmpty => all.isEmpty;
}

/// D26/E8：从服务端拿这个房间所有可用通道 + 服务端 primary。
///
/// 拿不到就返回空表 —— 老服务端没有 `addrs` 字段，不能因此进不了房。
Future<ChannelFetch> fetchChannels(String code, String base) async {
  final Dio dio = Dio(BaseOptions(
    baseUrl: base,
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 3),
  ));
  try {
    final Response<dynamic> r = await dio.get<dynamic>('/api/rooms/$code');
    final Object? raw =
        r.data is String ? jsonDecode(r.data as String) : r.data;
    if (raw is! Map) return ChannelFetch(<Channel>[], null, <String>[]);
    final Object? room = raw['room'];
    final Object? addrs = (room is Map ? room['addrs'] : null) ?? raw['addrs'];
    Channel? primary;
    final Object? pm = raw['primary'] ?? (room is Map ? room['primary'] : null);
    if (pm is Map) {
      final List<Channel> one = parseChannels(<Object?>[pm]);
      if (one.isNotEmpty) primary = one.first;
    }
    final List<String> rankedIds = <String>[];
    final Object? rk = raw['ranked'] ?? (room is Map ? room['ranked'] : null);
    if (rk is List) {
      for (final Object? e in rk) {
        if (e is Map && e['id'] is String) rankedIds.add(e['id'] as String);
      }
    }
    final List<Channel> parsed = parseChannels(addrs);
    if (parsed.isNotEmpty) {
      if (primary != null) {
        debugPrint('[YQK-CH] primary=${primary.id} ${primary.baseUrl} '
            'ranked=${rankedIds.join(",")}');
      }
      return ChannelFetch(parsed, primary, rankedIds);
    }
    // 详情接口本身不带 addrs（addrs 只随建房/分享接口下发），这时把当前 base
    // 当成唯一的局域网通道 —— 进房用的就是它，策略过滤也才有东西可筛。
    final Channel? self = _selfChannel(base);
    if (self != null) {
      debugPrint('[YQK-CH] addrs empty, fallback base=${self.baseUrl}');
      return ChannelFetch(<Channel>[self], null, <String>[]);
    }
    return ChannelFetch(<Channel>[], null, <String>[]);
  } on Object catch (e) {
    debugPrint('[YQK-CH] addrs fetch failed: $e');
    return ChannelFetch(<Channel>[], null, <String>[]);
  } finally {
    dio.close(force: true);
  }
}

/// D26：addrs 缺失时的兜底 —— 把当前 base 当成一条局域网通道。
Channel? _selfChannel(String base) {
  final Uri? u = Uri.tryParse(base);
  if (u == null || u.host.isEmpty) return null;
  return Channel(
    id: 'lan',
    name: '局域网',
    host: u.host,
    port: u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80),
    state: ChannelState.unknown,
  );
}

/// D26：TCP 端口探活 —— 能连上就算这条通道可达（HTTP 层的东西留给 /health）。
Future<bool> _probeChannel(String baseUrl) async {
  final Uri? u = Uri.tryParse(baseUrl);
  if (u == null || u.host.isEmpty) return false;
  final int port = u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
  try {
    final Socket s = await Socket.connect(
      u.host,
      port,
      timeout: const Duration(milliseconds: 800),
    );
    s.destroy();
    return true;
  } on Object {
    return false;
  }
}

/// D26/E8：按策略排好序后依次探活，第一条通的就是本次要用的通道。
/// 全部不通返回 null（调用方决定是提示还是回落）。
Future<Channel?> pickChannel(List<Channel> all, ChannelMode mode,
    {Channel? primary}) async {
  final Stopwatch sw = Stopwatch()..start();
  for (final Channel c in rankForMode(all, mode, primary: primary)) {
    if (await _probeChannel(c.baseUrl)) {
      debugPrint('[YQK-CH] pick mode=${channelModeToPref(mode)} '
          'n=${all.length} -> id=${c.id} cost=${sw.elapsedMilliseconds}ms');
      return c;
    }
  }
  debugPrint('[YQK-CH] pick mode=${channelModeToPref(mode)} '
      'all failed n=${all.length}');
  return null;
}

/// 建房：POST /api/rooms → 拿 code / room_token / ownerMemberId / memberToken。
Future<CreatedRoom?> createRoom({
  required String title,
  required String videoUrl,
  String base = kLocalServerBase,
}) async {
  final Dio dio = Dio(BaseOptions(
    baseUrl: base,
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 8),
    contentType: 'application/json',
  ));
  Response<dynamic> res;
  try {
    res = await dio.post<dynamic>(
      '/api/rooms',
      data: <String, Object?>{'name': title, 'video_url': videoUrl},
    );
  } on DioException {
    return null;
  } finally {
    dio.close(force: true);
  }

  if (res.statusCode != 200) return null;
  final Object? raw =
      res.data is String ? jsonDecode(res.data as String) : res.data;
  if (raw is! Map) return null;
  final Map<String, dynamic> body = Map<String, dynamic>.from(raw);
  final Object? rawRoom = body['room'];
  final Map<String, dynamic> room =
      rawRoom is Map ? Map<String, dynamic>.from(rawRoom) : body;
  String pick(String k) => (room[k] ?? body[k] ?? '').toString();

  final String code = pick('code');
  final String roomToken = pick('room_token');
  if (code.isEmpty || roomToken.isEmpty) return null;
  return CreatedRoom(
    code: code,
    roomToken: roomToken,
    ownerMemberId: pick('ownerMemberId'),
    memberToken: pick('memberToken'),
    videoUrl: (room['video_url'] ?? videoUrl).toString(),
    title: (room['name'] ?? title).toString(),
  );
}

/// 加入房间：POST /api/rooms/{code}/join → 拿 member.id / member.token。
/// 返回 null 表示房间不存在 / 服务没响应 / 已满。
class JoinedRoom {
  const JoinedRoom({required this.code, required this.memberId, required this.memberToken});
  final String code;
  final String memberId;
  final String memberToken;
}

/// 进房入口来源：文案与日志都按它区分（11 号 §9.2）。
enum JoinFrom {
  /// 首页弹窗手输
  manual,

  /// yiqikan://room/{code} 或 https://{host}/r/{code} 深链
  deeplink,

  /// 扫二维码
  scan,
}

extension JoinFromText on JoinFrom {
  /// 参数名（日志与深链 query 用同一套字符串）。
  String get tag => switch (this) {
        JoinFrom.manual => 'manual',
        JoinFrom.deeplink => 'deeplink',
        JoinFrom.scan => 'scan',
      };

  /// 进不去时给用户看的那一句话。
  String get failText => switch (this) {
        JoinFrom.manual => '房间码不对，或者房主没开',
        JoinFrom.deeplink => '这个链接打不开这个房间',
        JoinFrom.scan => '这个二维码不是进房码',
      };
}

/// 把 query 里的 from 字符串认回来，认不出按手动输入算。
JoinFrom joinFromOf(String? tag) {
  return switch (tag) {
    'deeplink' => JoinFrom.deeplink,
    'scan' => JoinFrom.scan,
    _ => JoinFrom.manual,
  };
}

/// 进房 HTTP 结果：成功带成员凭据，失败带服务端那句原因（"房间已满" / "room not found"）。
class JoinOutcome {
  const JoinOutcome.ok(JoinedRoom this.room) : error = '';
  const JoinOutcome.fail(this.error) : room = null;

  final JoinedRoom? room;
  final String error;

  bool get ok => room != null;
}

/// 加入房间：POST /api/rooms/{code}/join → 拿 member.id / member.token。
Future<JoinOutcome> joinRoom(
  String code, {
  String password = '',
  String base = kLocalServerBase,
}) async {
  final String c = code.trim().toUpperCase();
  if (c.isEmpty) return const JoinOutcome.fail('empty_code');
  final Dio dio = Dio(BaseOptions(
    baseUrl: base,
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 8),
    contentType: 'application/json',
  ));
  Response<dynamic> res;
  try {
    res = await dio.post<dynamic>(
      '/api/rooms/$c/join',
      data: <String, Object?>{
        'nickname': '客人',
        if (password.isNotEmpty) 'password': password,
      },
    );
  } on DioException catch (e) {
    // 4xx 也会走 DioException：满员是 400，body 里带着 {"error":"房间已满"}
    final Response<dynamic>? r = e.response;
    if (r != null) {
      final String why = _errorTextOf(r.data);
      debugPrint('[YQK-JOIN] http ${r.statusCode} code=$c error=$why');
      return JoinOutcome.fail(why.isEmpty ? 'http_${r.statusCode}' : why);
    }
    debugPrint('[YQK-JOIN] http failed code=$c error=$e');
    return const JoinOutcome.fail('offline');
  } finally {
    dio.close(force: true);
  }
  if (res.statusCode != 200) {
    final String why = _errorTextOf(res.data);
    return JoinOutcome.fail(why.isEmpty ? 'http_${res.statusCode}' : why);
  }
  final Object? raw =
      res.data is String ? jsonDecode(res.data as String) : res.data;
  if (raw is! Map) return const JoinOutcome.fail('bad_body');
  final Map<String, dynamic> body = Map<String, dynamic>.from(raw);
  final Object? rawMember = body['member'];
  final Map<String, dynamic> m =
      rawMember is Map ? Map<String, dynamic>.from(rawMember) : body;
  final String id = (m['id'] ?? '').toString();
  final String token = (m['token'] ?? m['memberToken'] ?? '').toString();
  if (id.isEmpty || token.isEmpty) return const JoinOutcome.fail('no_member');
  return JoinOutcome.ok(
    JoinedRoom(code: c, memberId: id, memberToken: token),
  );
}

/// 从服务端错误体里取一句可读原因（`error` → `detail` → `message`）。
String _errorTextOf(Object? data) {
  Object? raw = data;
  if (raw is String) {
    final String s = raw.trim();
    if (!s.startsWith('{')) return s;
    try {
      raw = jsonDecode(s);
    } catch (_) {
      return '';
    }
  }
  if (raw is! Map) return '';
  for (final String k in <String>['error', 'detail', 'message']) {
    final String v = (raw[k] ?? '').toString();
    if (v.isNotEmpty) return v;
  }
  return '';
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// 以客人身份进房：连房 → 进播放页（片源等房主的快照，页面里再开）。
///
/// 手输 / 深链 / 扫码三条入口共用这一条链，只有失败文案与日志前缀按 [from] 区分。
Future<bool> joinRoomAndEnter(
  BuildContext context,
  String code, {
  JoinFrom from = JoinFrom.manual,
  String password = '',
  String addr = '',
}) async {
  debugPrint('[YQK-JOIN] from=${from.tag} code=${code.trim().toUpperCase()}');
  // 分享链接里带着房主那台机器的地址（addr）：有就直接用，跳过通道探测。
  // 探测是 800ms/条，异地时 lan 那条必然白等一轮，用户体验上就是"点了没反应"。
  String pinned = addr.trim();
  while (pinned.endsWith('/')) {
    pinned = pinned.substring(0, pinned.length - 1);
  }
  if (pinned.isNotEmpty) {
    debugPrint('[YQK-JOIN] addr=$pinned (deeplink)');
  }
  // 只在这里问一次后端地址：下面 joinRoom / RoomClient 都用同一个 base，
  // 免得每个函数各查一次（多打四次 HTTP，还可能拿到不一致的地址）。
  final String base = pinned.isNotEmpty ? pinned : await resolveServerBase();
  debugPrint('[YQK-JOIN] join code=${code.trim().toUpperCase()} base=$base');
  final JoinOutcome outcome =
      await joinRoom(code, password: password, base: base);
  final JoinedRoom? joined = outcome.room;
  if (joined == null) {
    // 满员是服务端明说的事，比"房间码不对"精确，优先照原话提示
    final bool full = outcome.error.contains('房间已满') || outcome.error == '房间满了';
    if (context.mounted) {
      if (full) {
        _toast(context, '房间满了');
      } else {
        _toast(context, '进不去：${from.failText}');
      }
    }
    return false;
  }
  // D25：记下自己的房间码，附近的房间列表据此过滤掉自己
  lastRoomCode = joined.code;
  // D26：进房前选一次通道（AUTO 固定 lan → tunnel）。
  // addrs 拿不到（老服务端）就沿用 join 用的 base，不许因为选路把进房搞挂。
  String picked = base;
  Channel? pickedChannel;
  // E8：A-V4 要能从日志确认策略真的生效（设置页选了什么，进房就是什么）。
  // 放在分支外：深链（pinned 非空）不挑路，但同样要能看见当前策略。
  final Prefs prefs = await Prefs.open();
  final ChannelMode mode =
      channelModeFromPref(prefs.getString(PrefKeys.channelMode));
  debugPrint('[YQK-JOIN] mode=${channelModeToPref(mode)} '
      'code=${joined.code} label=${channelModeLabel(mode)} '
      'pinned=${pinned.isEmpty ? 'none' : pinned}');
  if (pinned.isNotEmpty) {
    // 地址来自分享链接，就不再挑路：挑成别的通道反而可能连到不通的那条，
    // 也与落地页上写的地址不一致。标记成 id='deeplink' 方便日志辨认。
    pickedChannel = Channel(id: 'deeplink', name: '分享链接', url: pinned);
  } else {
    final ChannelFetch fetch = await fetchChannels(joined.code, base);
    final List<Channel> chans = fetch.all;
    if (chans.isNotEmpty) {
      final Channel? best =
          await pickChannel(chans, mode, primary: fetch.primary);
      if (best != null) {
        picked = best.baseUrl;
        pickedChannel = best;
      } else {
        // 具体策略下一条都不通：说清楚，不许偷偷回落到别的通道。
        if (context.mounted) {
          if (mode == ChannelMode.forceTunnel) {
            _toast(context, '没有可用的隧道');
          } else if (mode == ChannelMode.lanOnly) {
            _toast(context, '没有可用的局域网');
          } else if (mode == ChannelMode.ipv6Only) {
            _toast(context, '没有可用的 IPv6 地址');
          }
        }
        return false;
      }
    }
  }
  final RoomClient client = RoomClient(
    baseUrl: picked,
    channel: pickedChannel,
    roomCode: joined.code,
    roomToken: '',
    deviceName: '客人',
    memberToken: joined.memberToken,
  );
  try {
    await client.connect();
    // 握手被 403 拒绝时服务端把原因写在 body 里（4004 满 / 4005 踢），
    // 这种情况下再 push 播放页只会得到一片黑，先把原因说清楚。
    final Map<String, dynamic>? hs = client.handshakeError;
    final int cc = (hs?['close_code'] as num?)?.toInt() ?? 0;
    if (cc == 4004 || cc == 4005) {
      if (!context.mounted) return false;
      _toast(context, cc == 4004 ? '房间满了' : '你被房主请出去了');
      return false;
    }
    if (!context.mounted) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => PlayerPage(
          media: PlayerMedia(
            id: 'room:${joined.code}',
            title: '一起看',
            url: '',
            sourceKind: 'direct',
          ),
          roomClient: client,
        ),
      ),
    );
    return true;
  } finally {
    await client.dispose();
  }
}


///
/// 只做这一条链（建房直接进播放页），扫码/深链进房留到下一步。
Future<void> createRoomAndEnter(
  BuildContext context, {
  required String title,
  required String videoUrl,
}) async {
  // 房主也走同一个 base：填了对方地址却在自己机器上建房，会变成
  // 「配置说连 A、房间其实开在 B」的半分裂状态，这里一并收口。
  final String base = await resolveServerBase();
  final CreatedRoom? created =
      await createRoom(title: title, videoUrl: videoUrl, base: base);
  if (created == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('建房失败，本地服务没响应')),
      );
    }
    return;
  }
  debugPrint('[YQK-JOIN] create code=${created.code} base=$base');
  // D25：自己的房间不进「附近的房间」
  lastRoomCode = created.code;

  final RoomClient client = RoomClient(
    baseUrl: base,
    roomCode: created.code,
    roomToken: created.roomToken,
    deviceName: '房主',
    memberToken: created.memberToken,
  );
  try {
    await client.connect();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => PlayerPage(
          media: PlayerMedia(
            id: 'room:${created.code}',
            title: created.title,
            url: created.videoUrl,
            sourceKind: 'direct',
          ),
          roomClient: client,
        ),
      ),
    );
  } finally {
    // 返回首页：释放连接与重连定时器，别让它在后台一直重试
    await client.dispose();
  }
}

