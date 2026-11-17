import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';

/// 最近一次进过的房间码：自己待过的房间不进「附近的房间」列表。
/// 由 room_entry 的建房/进房链路写入（D25 接收端）。
String? lastRoomCode;

/// 附近房间的一次广播快照（对应 UDP 包体六个字段里的 code/name/host/port/ts）。
class LanRoom {
  const LanRoom({
    required this.code,
    required this.name,
    required this.host,
    required this.port,
    required this.seenAt,
  });

  final String code;
  final String name;
  final String host;
  final int port;
  final DateTime seenAt;

  @override
  String toString() => 'LanRoom($code,$name,$host,$port)';
}

/// 只在房间列表页活着：绑定 45231 收房间广播，按 code 去重，6 秒没再听到就删掉。
///
/// 只收不发（发射端是服务端的 UdpBeacon，已验收），也不自动进房 —— 点卡片才进。
class LanDiscovery {
  LanDiscovery({this.onRooms, this.selfCode});

  void Function(List<LanRoom>)? onRooms;

  /// 自己的房间码，收到就丢（D25：不显示自己）
  String? selfCode;

  static const Duration _ttl = Duration(seconds: 6);

  RawDatagramSocket? _socket;
  Timer? _sweep;
  final Map<String, LanRoom> _rooms = <String, LanRoom>{};
  bool _running = false;

  bool get running => _running;
  int get count => _rooms.length;

  /// 绑不上（端口被占/模拟器无权限）返回 false，不抛。
  Future<bool> start() async {
    if (_running) return true;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
        reuseAddress: true,
      );
    } on Object catch (e) {
      debugPrint('[YQK-LAN] bind fail $kDiscoveryPort: $e');
      return false;
    }
    _running = true;
    debugPrint('[YQK-LAN] listen 0.0.0.0:$kDiscoveryPort');
    _socket!.listen(
      _onEvent,
      onError: (Object e) => debugPrint('[YQK-LAN] socket error $e'),
      cancelOnError: false,
    );
    _sweep = Timer.periodic(const Duration(seconds: 2), (_) => _sweepOnce());
    return true;
  }

  Future<void> stop() async {
    _running = false;
    _sweep?.cancel();
    _sweep = null;
    try {
      _socket?.close();
    } on Object catch (_) {
      // 关一个已经死掉的 socket 不值得炸页面
    }
    _socket = null;
    _rooms.clear();
    debugPrint('[YQK-LAN] stop');
  }

  void _onEvent(RawSocketEvent event) {
    final RawDatagramSocket? s = _socket;
    if (s == null || event != RawSocketEvent.read) return;
    final Datagram? d = s.receive();
    if (d == null) return;
    final LanRoom? room = parseLanPacket(d.data, selfCode: selfCode);
    if (room == null) return;
    _rooms[room.code] = room;
    debugPrint(
      '[YQK-LAN] recv code=${room.code} name=${room.name} host=${room.host} '
      'from=${d.address.address}:${d.port}',
    );
    _emit();
  }

  void _sweepOnce() {
    final DateTime now = DateTime.now();
    final int before = _rooms.length;
    _rooms.removeWhere((_, LanRoom r) => now.difference(r.seenAt) > _ttl);
    if (_rooms.length != before) {
      _emit();
    } else {
      debugPrint('[YQK-LAN] rooms=${_rooms.length}');
    }
  }

  void _emit() {
    debugPrint('[YQK-LAN] rooms=${_rooms.length}');
    onRooms?.call(_rooms.values.toList(growable: false));
  }
}

/// 包体解析（纯函数，单测直接打）：合法返回 LanRoom，坏包返回 null 并打一行日志。
///
/// 只认 `v == 1` 且 code 非空；`selfCode` 命中直接丢（不打 drop 日志，那不是坏包）。
LanRoom? parseLanPacket(
  List<int> data, {
  String? selfCode,
  DateTime? now,
}) {
  Map<String, dynamic>? m;
  try {
    final Object? raw = jsonDecode(utf8.decode(data));
    if (raw is Map) m = Map<String, dynamic>.from(raw);
  } on Object catch (_) {
    m = null;
  }
  if (m == null || m['v'] != 1) {
    debugPrint('[YQK-LAN] drop bad packet bytes=${data.length}');
    return null;
  }
  final String code = (m['code'] ?? '').toString().trim();
  if (code.isEmpty) {
    debugPrint('[YQK-LAN] drop bad packet bytes=${data.length}');
    return null;
  }
  final String? self = selfCode;
  if (self != null && self.isNotEmpty && code == self) return null;
  final Object? rawPort = m['port'];
  final int port =
      rawPort is num ? rawPort.toInt() : kDiscoveryPort;
  return LanRoom(
    code: code,
    name: (m['name'] ?? '').toString(),
    host: (m['host'] ?? '').toString(),
    port: port,
    seenAt: now ?? DateTime.now(),
  );
}
