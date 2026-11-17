import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpClientRequest, HttpClientResponse, WebSocket;

import 'package:flutter/foundation.dart';

import '../../data/local/secure_store.dart';
import '../../domain/entities/room_message.dart';
import 'bot_state.dart';
import 'channel.dart';
import 'host_change.dart';
import 'room_snapshot.dart';
import 'voice_client.dart';

/// 环形缓冲：满容量后按索引覆盖最旧的一条，不做 `removeAt(0)`。
///
/// 为什么不用 List：弹幕 500 条、每来一帧 removeAt(0) 就是 O(n) 搬移，
/// 连发时会把 UI 线程拖住；这里写入恒为 O(1)，只有取快照时才复制一次。
class _Ring<T> {
  _Ring(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<T> _buf = <T>[];
  int _head = 0;

  int get length => _buf.length;
  bool get isEmpty => _buf.isEmpty;

  void add(T v) {
    if (_buf.length < capacity) {
      _buf.add(v);
    } else {
      _buf[_head] = v;
      _head = (_head + 1) % capacity;
    }
  }

  /// 按时间顺序（最旧 → 最新）复制一份，供 ValueNotifier 投影。
  List<T> toList() {
    if (_buf.length < capacity) return List<T>.of(_buf);
    return <T>[for (int i = 0; i < capacity; i++) _buf[(_head + i) % capacity]];
  }

  /// 命中并删除时返回 true；没命中返回 false（撤回想撤回一条不存在的记录不算错）。
  bool removeWhere(bool Function(T) test) {
    final List<T> now = toList();
    final List<T> kept = now.where((T e) => !test(e)).toList();
    if (kept.length == now.length) return false;
    _buf
      ..clear()
      ..addAll(kept);
    _head = 0;
    return true;
  }

  void clear() {
    _buf.clear();
    _head = 0;
  }
}

/// 强序帧（与服务端 `LocalServer.SEQ_FRAMES` 一一对应）。
///
/// 为什么这么分：只有「业务事件」需要严格顺序和重连后补发判据；
/// progress/status 这类高频覆盖帧如果也带 seq，会把判据淹没在每秒几条里。
const Set<String> kSeqFrames = <String>{
  'joined', 'kicked', 'muted', 'members', 'state', 'sync', 'control', 'claim', 'web',
  'select', 'next', 'ended', 'rate', 'quality', 'settings', 'setHost',
  'setMuted', 'setNotice', 'notice', 'chat', 'chat-recall', 'danmaku',
  'danmaku-like', 'danmaku-likes', 'reaction', 'media', 'media-add', 'vote',
  'vote-cast', 'vote-result', 'summon', 'teleport', 'screen', 'voice',
  'voice-error', 'voice-full', 'voice-state', 'ice', 'offer', 'sdp',
  'room-closed', 'error',
};

/// 覆盖式帧：后到覆盖先到，只保留最新一条，200ms 最多发一条。
///
/// 为什么单独处理：progress 每秒好几条，如果和弹幕抢 128 的队列，
/// 弹幕一多进度就被挤掉，房主那边会看到「进度条不动」。
const Set<String> kCoalescedFrames = <String>{'progress', 'status', 'quality', 'rate'};

/// 可丢帧：队列满时优先被挤掉（高频、丢了不影响状态机正确性）。
///
/// voice-state 不在这里面：它是全量低频帧，丢了就只能等下一次 join/leave，
/// 而 sync 快照不带 voice —— 丢一条就少一个人的 🎤，得不偿失。
const Set<String> kDroppableFrames = <String>{
  'chat', 'danmaku', 'danmaku-like', 'danmaku-likes', 'reaction', 'speaking',
};

/// 关键帧：队列打满也一条不丢（改房主、改片、控制这类一旦丢就状态分叉）。
const Set<String> kCriticalFrames = <String>{
  'hello', 'control', 'claim', 'select', 'next', 'ended', 'setHost', 'setMuted',
  'setNotice', 'settings', 'media', 'media-add', 'kick', 'room-closed',
};

/// 房间连接的传输层抽象。
///
/// 真实实现在 `_IoWebSocketTransport`；单测注入假实现，就能在不起 socket
/// 的情况下验证 seq 单调、过期帧丢弃、发送队列背压。
abstract class RoomTransport {
  /// 文本帧流（服务端只发文本）。
  Stream<String> get messages;

  /// 关闭码；断线时为 null（异常断开）。
  int? get closeCode;

  void send(String text);

  Future<void> close([int code = 1000, String reason = '']);
}

/// 用 `dart:io` 的 WebSocket 建传输。
typedef RoomTransportFactory = Future<RoomTransport> Function(Uri uri);

class RoomClientState {
  const RoomClientState(this.name);

  final String name;

  static const RoomClientState idle = RoomClientState('idle');
  static const RoomClientState connecting = RoomClientState('connecting');
  static const RoomClientState connected = RoomClientState('connected');
  static const RoomClientState reconnecting = RoomClientState('reconnecting');
  static const RoomClientState failed = RoomClientState('failed');
  static const RoomClientState closed = RoomClientState('closed');

  @override
  String toString() => name;
}

/// 房间客户端：只管「连/断/重连/收发/seq」，帧的业务语义留给上层（第 2 步）。
///
/// 三条硬约束（12 号 §3 + m08624）：
/// 1. `seq` 由服务端给，客户端只记 `lastSeq`；重连时用 `lastSeq + 1` 续，
///    不请求整房重放。
/// 2. 发送走队列，队列超过 [maxQueue] 就丢最老的（背压），不无限堆积。
/// 3. 每帧打一行 `[YQK-ROOM] tx=/rx= type= seq=`，便于真机取证。
class RoomClient {
  /// 进程内最近一次 connect 过的客户端（G6 诊断页只读用）。
  static RoomClient? current;

  RoomClient({
    required this.baseUrl,
    required this.roomCode,
    required this.roomToken,
    required this.deviceName,
    String? memberToken,
    RoomTransportFactory? transportFactory,
    this.channel,
    this.maxQueue = 128,
  })  : _memberToken = memberToken,
        _transportFactory = transportFactory ?? _ioTransport;

  /// 房间 HTTP 基地址，如 `http://192.168.1.8:8080`（只用来拼 ws://）。
  final String baseUrl;

  /// D26：本次连接用的通道（进房时选路选出来的赢家）。没选过路就是 null，
  /// 健康检查这时按 [baseUrl] 走、日志里 id 记 lan。
  final Channel? channel;
  final String roomCode;
  final String roomToken;
  final String deviceName;

  /// 发送队列上限（背压水位）。
  final int maxQueue;

  final RoomTransportFactory _transportFactory;

  final StreamController<RoomClientState> _states =
      StreamController<RoomClientState>.broadcast();

  /// 收到的所有文本帧（业务分发在上层）。
  final StreamController<Map<String, dynamic>> _frames =
      StreamController<Map<String, dynamic>>.broadcast();

  /// 唯一的房间快照（hello / state / members 帧就地更新，UI 只读这里）
  final ValueNotifier<RoomSnapshot?> _snapshot = ValueNotifier<RoomSnapshot?>(null);

  /// 每个人的播放进度（progress 帧就地覆盖，Map 只有一份）
  final ValueNotifier<Map<String, MemberProgress>> _progress =
      ValueNotifier<Map<String, MemberProgress>>(<String, MemberProgress>{});

  ValueListenable<RoomSnapshot?> get snapshot => _snapshot;

  /// 房主换人了：值是给用户看的一句话（空串表示这次变化不值得提示）。
  /// 播放页监听它弹 SnackBar；判断逻辑在 hostChangeText()（纯函数，单测覆盖）。
  final ValueNotifier<String> hostNotice = ValueNotifier<String>('');

  /// 服务端语音总开关（GET /local/features）。false 时入口整个不渲染。
  /// 拉取失败保持 true：网络抖一下不该把语音按钮弄没。
  final ValueNotifier<bool> voiceEnabled = ValueNotifier<bool>(true);

  /// 房间 Bot 的当前配置（D27）：服务端 `bot-state` 全量覆盖；null = 还没配过。
  /// 与 voiceEnabled 一样，只反映服务端状态，不落 SharedPreferences。
  final ValueNotifier<BotState?> botState = ValueNotifier<BotState?>(null);

  /// I-44：被房主移出的提示语。自己那条连接会先收到 close(4005) 走
  /// `_onClosed` 的「不重连」，所以这个值正常情况下不会出现；
  /// `kicked` 帧是给房里其他人看的。留着兜住两端。
  final ValueNotifier<String?> _kickNotice = ValueNotifier<String?>(null);

  ValueListenable<String?> get kickNotice => _kickNotice;

  /// D22：房间一起看网页的帧（open / scroll / close）。
  /// 走 `web` 帧 + 现有 seq 通道，页面侧只订阅这个流，不自己解析 WS。
  final StreamController<Map<String, dynamic>> _webEvents =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get webEvents => _webEvents.stream;


  /// 快照唯一入口：顺手比对 hostId，房主一变就发一条 hostNotice
  void _setSnapshot(RoomSnapshot? next) {
    if (next == null) return;
    final RoomSnapshot? prev = _snapshot.value;
    _snapshot.value = next;
    final String text = hostChangeText(
      before: prev?.hostId,
      after: next.hostId,
      me: memberId ?? '',
    );
    if (text.isNotEmpty) {
      debugPrint('[YQK-ROOM] host 变更 $text host=$next.hostId me=$memberId');
      hostNotice.value = text;
    }
  }

  ValueListenable<Map<String, MemberProgress>> get progress => _progress;

  /// 权威播放位置（state 帧），跟随/落后秒数都算它
  final ValueNotifier<Duration?> _authoritative = ValueNotifier<Duration?>(null);

  /// state 帧的基准值：position + **收到帧那一刻启动的本地单调时钟** + 是否在播 + 倍速。
  /// 不能拿帧里的服务端时间戳做差：盒子和电视常常不走 NTP，两台机差几秒，
  /// `now - updatedAt` 会变成负数（把客人拉回过去）或虚高（一直往前跳）。
  /// 用 Stopwatch 而不是 DateTime.now()：改系统时间/时区/NTP 校时都会让后者跳变。
  Duration _authBase = Duration.zero;
  Stopwatch? _authClock;
  bool _authPlaying = false;
  double _authRate = 1;
  String? _authBy;

  /// 最近一条权威 state 是谁发的（防自激用；服务端填 by）
  String? get authoritativeBy => _authBy;

  /// 权威三件套：播放状态 / 倍速 / 当前位置。
  /// 房间的「实时状态」只有这一个来源；snapshot 是进房那一刻的快照，别当实时值用。
  bool get authoritativePlaying => _authPlaying;
  double get authoritativeRate => _authRate;

  /// 已经按本地单调时钟外推过，外面不要再外推第二次
  Duration? get authoritativePosition => _authClock == null ? _authoritative.value : _expectedNow();

  /// state 帧里带的片源（换片跟随用）；没带过就是 null
  String? _authMediaUrl;
  String? get authoritativeMediaUrl => _authMediaUrl;

  /// 收到帧后过了多少毫秒（本地单调时钟）；没有基准时返回 null
  int? get authoritativeElapsedMs {
    final Stopwatch? c = _authClock;
    if (c == null) return null;
    return c.elapsedMilliseconds + _authClockSkewMs;
  }

  /// 只给单测用：把本地单调时钟往前拨，避免靠 sleep 等真实时间
  @visibleForTesting
  void debugAdvanceAuthClock(Duration d) {
    _authClockSkewMs += d.inMilliseconds;
  }

  /// 只给单测用：直接喂一条帧，走和真连接一样的 _onFrame 路径
  @visibleForTesting
  void debugFeedFrame(Map<String, dynamic> j) => _onFrame(jsonEncode(j));

  int _authClockSkewMs = 0;

  Duration _expectedNow() {
    final Stopwatch? c = _authClock;
    if (c == null || !_authPlaying) return _authBase;
    final int elapsedMs =
        (c.elapsedMilliseconds + _authClockSkewMs).clamp(0, 3600 * 1000);
    return _authBase + Duration(milliseconds: (elapsedMs * _authRate).round());
  }

  /// 当前应有的位置（每次读都按本地时钟外推，UI 每秒刷一次就能看到秒数在动）
  Duration? get expectedPosition {
    if (_authClock == null) return _authoritative.value;
    return _expectedNow();
  }

  ValueListenable<Duration?> get authoritative => _authoritative;

  /// 通知计数器：state 帧每来一条就 +1。
  /// 不能只靠 [_authoritative] 通知：ValueNotifier 在「值相等」时不发通知，
  /// 而「同一秒播放中 → 同一秒已暂停」算出来的位置完全相等，播放态变化会被吞。
  final ValueNotifier<int> _authTick = ValueNotifier<int>(0);
  /// 房主侧：当前待审批的控制请求（null 表示没有）
  final ValueNotifier<Map<String, dynamic>?> _pending = ValueNotifier<Map<String, dynamic>?>(null);
  ValueListenable<Map<String, dynamic>?> get pendingClaim => _pending;
  /// 发起者侧：最近一条被拒/超时的请求
  final ValueNotifier<Map<String, dynamic>?> _rejected = ValueNotifier<Map<String, dynamic>?>(null);
  ValueListenable<Map<String, dynamic>?> get rejectedClaim => _rejected;
  /// 自己的 claim 被批准时 +1：发起者自己也要 apply 一次（服务端广播的 by 就是发起者，
  /// shouldFollowState 会把它当自激 skip 掉，必须靠这条强制应用）。
  final ValueNotifier<int> _claimGranted = ValueNotifier<int>(0);
  ValueListenable<int> get claimGranted => _claimGranted;
  ValueListenable<int> get authTick => _authTick;

  /// 客人侧：房主换片源时收到的 media 帧（null 表示还没收到过）。
  /// 用 ValueNotifier 而非新造回调链，跟 pendingClaim / rejectedClaim 同一套通知机制。
  final ValueNotifier<Map<String, dynamic>?> _mediaFrame =
      ValueNotifier<Map<String, dynamic>?>(null);
  ValueListenable<Map<String, dynamic>?> get mediaFrame => _mediaFrame;
  /// 换成同一部片后立刻清空，避免重复 apply（同一 url 再来一次会因为
  /// ValueNotifier 值相等而不通知，但先清空语义更明确）。
  void clearMediaFrame() => _mediaFrame.value = null;

  // ---------- E：六帧数据通道（只做数据，不碰 UI） ----------

  /// 聊天：最多 200 条（环形覆盖最旧）
  final _Ring<ChatMessage> _chatRing = _Ring<ChatMessage>(200);
  final ValueNotifier<List<ChatMessage>> _chats =
      ValueNotifier<List<ChatMessage>>(const <ChatMessage>[]);
  ValueListenable<List<ChatMessage>> get chats => _chats;

  /// 弹幕：最多 500 条（环形索引，连发不搬移）
  final _Ring<RoomDanmaku> _danmakuRing = _Ring<RoomDanmaku>(500);
  final ValueNotifier<List<RoomDanmaku>> _danmakus =
      ValueNotifier<List<RoomDanmaku>>(const <RoomDanmaku>[]);
  ValueListenable<List<RoomDanmaku>> get danmakus => _danmakus;

  /// debug 专用：把一条本地构造的弹幕塞进环形缓冲。
  ///
  /// 为什么需要：服务端 relay 会跳过发送者（日志里的 `relay skip self`），
  /// 所以「自己发的那条」永远收不到回显帧；要验证「发送后立刻可见、位置对齐」
  /// 就必须在本地自回显一次。只给 debug 菜单用，不影响任何真实帧路径。
  void debugInjectDanmaku(RoomDanmaku item) {
    _danmakuRing.add(item);
    _danmakus.value = _danmakuRing.toList();
    debugPrint('[YQK-ROOM] danmaku 本地回显 id=${item.id} pos=${item.pos}');
  }

  /// 本地塞一条自己发的聊天。
  ///
  /// 服务端 relay 跳过发送者（`relay skip self`），所以自己发的话不会从
  /// WebSocket 回来；不做本地回显，说话人就只能看到别人的消息，自己的气泡
  /// 永远不出现。id 用 `local_` 前缀，方便和服务端 `ch_` 的 id 区分。
  void injectLocalChat(ChatMessage m) {
    _chatRing.add(m);
    _chats.value = _chatRing.toList();
    debugPrint('[YQK-ROOM] chat 本地回显 id=${m.id} kind=${m.kind}');
  }

  /// 弹幕点赞数：danmakuId → n（danmaku-like 自增，danmaku-likes 覆盖）
  final ValueNotifier<Map<String, int>> _danmakuLikes =
      ValueNotifier<Map<String, int>>(const <String, int>{});
  ValueListenable<Map<String, int>> get danmakuLikes => _danmakuLikes;

  /// 语音成员（M8 7a）：服务端 voice-state 全量覆盖，joined 由自己的 memberId 算。
  final ValueNotifier<VoiceState> _voiceState =
      ValueNotifier<VoiceState>(VoiceState.empty);
  ValueListenable<VoiceState> get voiceState => _voiceState;

  /// 语音的一次性提示（满员 / 报错）。和 hostNotice 一样：只放文本，谁弹 SnackBar 由页面决定。
  final ValueNotifier<String> voiceNotice = ValueNotifier<String>('');

  /// offer / sdp / ice 三类单播信令的出口。由 player_page 挂到 VoiceEngine.onSignal。
  void Function(Map<String, dynamic> frame)? onP2P;

  /// 房主下发 Bot 配置（D27）。服务端只认房主，非房主会收到 not_host 错误帧。
  /// 字段全部走参数，配置页负责给默认值与合法性校验。
  void sendBotConfig({required Map<String, dynamic> cfg}) =>
      send(<String, dynamic>{'type': 'bot-config', ...cfg});

  /// 三条上行指令。帧名只能是 SEQ_FRAMES 里的 voice，动作靠 action 区分。
  void sendVoiceJoin() => send(<String, dynamic>{'type': 'voice', 'action': 'join'});
  void sendVoiceLeave() => send(<String, dynamic>{'type': 'voice', 'action': 'leave'});
  void sendVoiceMute(bool muted) =>
      send(<String, dynamic>{'type': 'voice', 'action': 'mute', 'muted': muted});

  /// 点赞帧的合并规则（M8 点赞，2026-11-08）：
  /// - `danmaku-likes` 是服务端权威计数（`items` 里一条或多条），逐条并入，取 **max**。
  ///   必须 max 不能覆盖：本地乐观 +1 刚写进去，服务端回来的可能是同一份旧值，
  ///   直接覆盖会让数字回跳（用户看到 +1 闪一下又变回 0）。
  /// - `danmaku-like` 是别人点赞的转发帧（没有计数字段），只当通知、不改计数（计数只认 danmaku-likes）。
  void _applyDanmakuLikes(Map<String, dynamic> j, String type) {
    final Map<String, int> next = mergeDanmakuLikes(_danmakuLikes.value, j, type);
    if (!identical(next, _danmakuLikes.value)) {
      _danmakuLikes.value = next;
    }
    debugPrint('[YQK-ROOM] $type 合并 likes=$next');
  }

  /// 自己点了个赞：本地先 +1（乐观更新），服务端 `danmaku-likes` 回来走 max 合并。
  void bumpDanmakuLike(String id) {
    if (id.isEmpty) return;
    final int n = (_danmakuLikes.value[id] ?? 0) + 1;
    _danmakuLikes.value = <String, int>{..._danmakuLikes.value, id: n};
    debugPrint('[YQK-DM] like id=$id count=$n');
  }

  /// 表情回应：最多 100 条
  final _Ring<ReactionItem> _reactionRing = _Ring<ReactionItem>(100);
  final ValueNotifier<List<ReactionItem>> _reactions =
      ValueNotifier<List<ReactionItem>>(const <ReactionItem>[]);
  ValueListenable<List<ReactionItem>> get reactions => _reactions;

  /// 是否已经进过房（区分「首次进房清空」和「重连保留」）
  bool _joinedOnce = false;
  bool get joinedOnce => _joinedOnce;

  void _clearHistory() {
    _chatRing.clear();
    _danmakuRing.clear();
    _reactionRing.clear();
    _chats.value = const <ChatMessage>[];
    _danmakus.value = const <RoomDanmaku>[];
    _reactions.value = const <ReactionItem>[];
    _danmakuLikes.value = const <String, int>{};
  }

  RoomTransport? _transport;
  StreamSubscription<String>? _sub;
  Timer? _retryTimer;
  Timer? _pingTimer;

  RoomClientState _state = RoomClientState.idle;
  int _retry = 0;

  /// 握手被服务端拒绝时 403 响应的 body（`{ok,error,close_code}`）。
  ///
  /// 为什么还要单独探一次：`WebSocket.connect` 失败只会抛
  /// `WebSocketException: ... was not upgraded to websocket`，状态码和 body 都拿不到；
  /// 而服务端现在把 kicked(4005) / room_full(4004) 写在 101 之前的 403 body 里，
  /// 所以失败后补一个普通 HTTP 请求，把那段 body 读回来，界面才能提示「房间满了」
  /// 而不是只看到 1006。
  Map<String, dynamic>? _handshakeError;

  /// 服务端最近一次给的 seq；-1 表示还没收到。
  int _lastSeq = -1;

  /// 本地发出的帧计数（只用于日志，不是协议 seq）。
  int _txSeq = 0;

  /// 背压队列。
  final List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];

  /// 覆盖式帧的合并槽（type → 最新一帧），不进 [_queue]。
  final Map<String, Map<String, dynamic>> _coalesced = <String, Map<String, dynamic>>{};
  Timer? _coalesceTimer;
  int _dropped = 0;

  String? _memberId;
  String? _memberToken;

  /// 进程内的成员身份（不落 prefs，跟 SecureStore 一个口径：重启即重新握手）。
  String? get memberId => _memberId;
  String? get memberToken => _memberToken;

  /// I-81：memberToken 的落盘键（按房间码分开，一台手机可能进过多个房间）。
  String get _memberTokenKey => 'room_member_$roomCode';

  final SecureStore _secure = SecureStore();

  /// 把这次握手拿到的 memberToken 存起来，下次重进房用它复用同一个 memberId。
  Future<void> _persistMemberToken() async {
    final String? t = _memberToken;
    if (t == null || t.isEmpty) return;
    await _secure.put(_memberTokenKey, t);
  }

  /// 进程重启后把上次的 memberToken 读回来（读不到就当新成员）。
  Future<void> _restoreMemberToken() async {
    if (_memberToken != null && _memberToken!.isNotEmpty) return;
    final String? t = await _secure.get(_memberTokenKey);
    if (t != null && t.isNotEmpty) {
      _memberToken = t;
      debugPrint('[YQK-ROOM] memberToken restored room=$roomCode');
    }
  }

  RoomClientState get state => _state;
  int get lastSeq => _lastSeq;
  int get droppedCount => _dropped;
  int get queuedCount => _queue.length;

  /// 握手被拒时的服务端回执（status / error / close_code / body）；没被拒则为 null。
  Map<String, dynamic>? get handshakeError => _handshakeError;

  Stream<RoomClientState> get states => _states.stream;
  Stream<Map<String, dynamic>> get frames => _frames.stream;

  /// 拼 ws 地址：`http(s)://host:port` → `ws(s)://host:port/ws?room=…&token=…`
  /// 带 `member_token` 时服务端会复用同一 memberId（房主拿建房下发的 token 即可复用 host 身份）。
  Uri get wsUri {
    final Uri b = Uri.parse(baseUrl);
    final Map<String, String> q = <String, String>{
      'room': roomCode,
      'token': roomToken,
    };
    if (_memberToken != null && _memberToken!.isNotEmpty) {
      q['member_token'] = _memberToken!;
    }
    return b.replace(
      scheme: b.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: q,
    );
  }

  /// 仅探针/测试用：模拟一次网络断开（触发自动重连），身份与本地历史都不动。
  ///
  /// 1001 = going away（1006 是保留码，WebSocket 层不许客户端主动发）。
  @visibleForTesting
  Future<void> debugDropConnection() async {
    try {
      await _transport?.close(1001, 'probe drop');
    } catch (_) {
      // 已经断了就算了
    }
  }

  Future<void> connect() async {
    // G6 诊断页要读「当前用的哪条通道 / 哪个房间」，进程内单房间场景够用。
    // 退房不置空：诊断页希望看到「上一次进的房」，比空着有用。
    RoomClient.current = this;
    if (_state == RoomClientState.connected) return;
    _setState(RoomClientState.connecting);
    // I-81：先把上次的 memberToken 捞回来，握手时才带得上（重进房不新增成员）。
    await _restoreMemberToken();
    final bool resuming = _lastSeq >= 0;
    try {
      final RoomTransport t = await _transportFactory(wsUri)
          .timeout(const Duration(seconds: 5));
      _transport = t;
      _sub = t.messages.listen(
        _onFrame,
        onDone: _onClosed,
        onError: (Object _) => _onClosed(),
      );
      _setState(RoomClientState.connected);
      _retry = 0;

      // 握手：带上 memberToken 让服务端复用成员；带上 lastSeq+1 让服务端知道续传起点。
      send(<String, dynamic>{
        'type': 'hello',
        'protocol': 1,
        'room': roomCode,
        'name': deviceName,
        if (_memberId != null) 'memberId': _memberId,
        if (_memberToken != null) 'memberToken': _memberToken,
        'lastSeq': _lastSeq + 1,
      }, critical: true);
      if (resuming) {
        debugPrint('[YQK-ROOM] resume from seq=${_lastSeq + 1}（不整房重放）');
      }
      _startPing();
      _startHealth();
      _flushQueue();
    } catch (e) {
      debugPrint('[YQK-ROOM] connect failed: $e');
      final Map<String, dynamic>? hs = await _probeHandshake();
      if (hs != null) {
        _handshakeError = hs;
        debugPrint('[YQK-ROOM] handshake reject status=${hs['status']} '
            'error=${hs['error']} close_code=${hs['close_code']} body=${hs['body']}');
      }
      final int cc = (_handshakeError?['close_code'] as num?)?.toInt() ?? 0;
      if (cc == 4004 || cc == 4005) {
        // 房间满 / 被踢：重连一万次也进不去，直接收敛成 closed，把原因交给界面。
        _setState(RoomClientState.closed);
        return;
      }
      _setState(RoomClientState.reconnecting);
      _scheduleReconnect();
    }
  }

  /// 握手失败后补一次普通 HTTP 请求，把 403 的 body 读回来（见 [_handshakeError]）。
  Future<Map<String, dynamic>?> _probeHandshake() async {
    HttpClient? c;
    try {
      final Uri u = wsUri.replace(
        scheme: wsUri.scheme == 'wss' ? 'https' : 'http',
      );
      c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final HttpClientRequest req = await c.getUrl(u);
      req.headers.set('Connection', 'Upgrade');
      req.headers.set('Upgrade', 'websocket');
      req.headers.set('Sec-WebSocket-Version', '13');
      req.headers.set('Sec-WebSocket-Key', 'eWlxaWthbi1wcm9iZS1yZWNvbm4=');
      final HttpClientResponse res = await req.close();
      final String body = await res.transform(utf8.decoder).join();
      final Map<String, dynamic> out = <String, dynamic>{'status': res.statusCode};
      if (body.trim().startsWith('{')) {
        final Object? j = jsonDecode(body);
        if (j is Map) out.addAll(Map<String, dynamic>.from(j));
      }
      out['body'] = body;
      return out;
    } catch (e) {
      debugPrint('[YQK-ROOM] handshake probe failed: $e');
      return null;
    } finally {
      c?.close(force: true);
    }
  }

  /// 拉一次服务端语音总开关（GET /local/features）。
  ///
  /// 失败一律保持 true：这是「隐藏入口」用的提示位，不能因为一次请求超时
  /// 就把功能从 UI 上抹掉。成功后服务端拒绝加入仍由 voice-error 兜底。
  Future<void> _loadFeatures() async {
    HttpClient? c;
    try {
      final Uri u = Uri.parse(baseUrl).resolve('/local/features');
      c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final HttpClientRequest req = await c.getUrl(u);
      final HttpClientResponse res = await req.close();
      final String body = await res.transform(utf8.decoder).join();
      if (!body.trim().startsWith('{')) return;
      final Object? j = jsonDecode(body);
      if (j is! Map) return;
      final Object? on = j['voiceEnabled'];
      if (on is bool) {
        voiceEnabled.value = on;
        debugPrint('[YQK-VOICE] features voiceEnabled=$on');
      }
    } catch (e) {
      debugPrint('[YQK-VOICE] features fail ${e.runtimeType}');
    } finally {
      c?.close(force: true);
    }
  }

  /// 有人进/出房时把成员表拉一次。
  ///
  /// 服务端只在「禁言 / 移交房主 / 批准」时广播 members 帧，普通进房只发 joined
  /// （帧里不带 room）。不补这一下，房主那边的成员条会一直停在「只有自己」——
  /// 双机验收里就是「A 看不见 B」。走 HTTP 读只读快照，不改任何协议帧。
  Future<void> _refreshMembers() async {
    HttpClient? c;
    try {
      final Uri u = Uri.parse(baseUrl).resolve('/api/rooms/$roomCode');
      c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final HttpClientRequest req = await c.getUrl(u);
      final HttpClientResponse res = await req.close();
      final String body = await res.transform(utf8.decoder).join();
      if (!body.trim().startsWith('{')) return;
      final Object? j = jsonDecode(body);
      if (j is! Map) return;
      final Object? room = j['room'];
      if (room is! Map) return;
      final RoomSnapshot? cur = _snapshot.value;
      final Object? list = room['members'];
      if (cur == null || list is! List) return;
      final List<RoomMember> ms = <RoomMember>[
        for (final Object? one in list)
          if (one is Map) RoomMember.fromJson(Map<String, dynamic>.from(one)),
      ];
      final String hostId = (room['host'] ?? room['host_id'] ?? '').toString();
      _setSnapshot(cur.withMembers(ms, hostId: hostId));
      debugPrint('[YQK-ROOM] refresh members=${ms.length} host=$hostId');
    } catch (e) {
      debugPrint('[YQK-ROOM] refresh members failed: $e');
    } finally {
      c?.close(force: true);
    }
  }

  /// 发一帧。
  ///
  /// 三类处理（见文件顶部三张集合）：
  /// - 覆盖式帧（progress/status/quality/rate）不进队列，按 type 合并，200ms 最多发一条；
  /// - 其余帧进队列，队列满时先挤 [_droppable] 里最老的，挤不到才丢当前帧；
  /// - [_critical] 永不许丢。
  /// D22：一起看网页（open / scroll / close）。只做一层 `type` 包装，
  /// seq 由服务端按 `web` 走现有强序通道补。
  void sendWeb(Map<String, dynamic> w) =>
      send(<String, dynamic>{'type': 'web', ...w});

  void send(Map<String, dynamic> frame, {bool critical = false}) {
    final String type = (frame['type'] as String?) ?? '';
    final bool isCritical = critical || kCriticalFrames.contains(type);

    // 覆盖式帧：永远走后合并通道，不占队列额度
    if (kCoalescedFrames.contains(type) && !isCritical) {
      assert(!_queue.any((Map<String, dynamic> f) => f['type'] == type),
          '覆盖式帧不许进队列：$type');
      _coalesced[type] = frame;
      _scheduleCoalescedFlush();
      return;
    }

    if (_state == RoomClientState.connected && _transport != null) {
      _writeNow(frame);
      return;
    }
    if (_queue.length >= maxQueue) {
      final int victim = _queue.indexWhere(
          (Map<String, dynamic> f) => f['_critical'] != true && kDroppableFrames.contains(f['type']));
      if (victim >= 0) {
        _queue.removeAt(victim);
        _dropped++;
      } else if (!isCritical) {
        _dropped++;
        debugPrint('[YQK-ROOM] drop type=$type（队列满 $_queue.length/$maxQueue，累计丢 $_dropped）');
        return;
      } else {
        // 只有 critical 帧在排队，且当前也是 critical：只能挤最老的
        final int oldestNonCritical = _queue.indexWhere((Map<String, dynamic> f) => f['_critical'] != true);
        if (oldestNonCritical >= 0) {
          _queue.removeAt(oldestNonCritical);
          _dropped++;
        } else {
          _queue.removeAt(0);
          _dropped++;
        }
      }
    }
    _queue.add(<String, dynamic>{...frame, '_critical': isCritical});
  }

  /// 禁言 / 解除禁言（只有房主能成）。
  ///
  /// 服务端成功会回一帧 `muted`（带 memberId），失败回 `error`；
  /// 所以这里不回 void，等那帧到了再 true，让 UI 能说「已禁言 XXX」而不是瞎报成功。
  Future<bool> setMuted(String memberId, bool muted) {
    final String rid = 'mu-${DateTime.now().microsecondsSinceEpoch}';
    final Completer<bool> done = Completer<bool>();
    _muteWaiters.add(done);
    send(<String, dynamic>{
      'type': 'setMuted',
      'memberId': memberId,
      'muted': muted,
      'rid': rid,
    });
    return done.future.timeout(const Duration(seconds: 3), onTimeout: () {
      _muteWaiters.remove(done);
      debugPrint('[YQK-ROOM] setMuted timeout memberId=$memberId muted=$muted');
      return false;
    });
  }

  /// 等服务端确认的禁言请求（`muted` 帧 true，`error` 帧 false）
  final List<Completer<bool>> _muteWaiters = <Completer<bool>>[];

  void _settleMuteWaiters({required bool ok}) {
    for (final Completer<bool> c in List<Completer<bool>>.of(_muteWaiters)) {
      if (!c.isCompleted) c.complete(ok);
    }
    _muteWaiters.clear();
  }

  void _scheduleCoalescedFlush() {
    _coalesceTimer ??= Timer(const Duration(milliseconds: 200), () {
      _coalesceTimer = null;
      _flushCoalesced();
    });
  }

  void _flushCoalesced() {
    if (_coalesced.isEmpty) return;
    final List<Map<String, dynamic>> batch =
        _coalesced.values.map((Map<String, dynamic> f) => f).toList();
    _coalesced.clear();
    for (final Map<String, dynamic> f in batch) {
      _writeNow(f);
    }
  }

  void _writeNow(Map<String, dynamic> raw) {
    final Map<String, dynamic> frame = Map<String, dynamic>.of(raw)..remove('_critical');
    final String text = jsonEncode(frame);
    _txSeq++;
    try {
      _transport?.send(text);
      debugPrint('[YQK-ROOM] tx=${frame['type']} seq=$_txSeq len=${text.length}');
    } catch (e) {
      debugPrint('[YQK-ROOM] tx failed: $e');
    }
  }

  void _flushQueue() {
    if (_queue.isEmpty) return;
    final List<Map<String, dynamic>> pending = List<Map<String, dynamic>>.of(_queue);
    _queue.clear();
    for (final Map<String, dynamic> f in pending) {
      _writeNow(f);
    }
  }

  void _onFrame(String raw) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      debugPrint('[YQK-ROOM] rx bad json len=${raw.length}');
      return;
    }
    final String type = (j['type'] as String?) ?? '';
    final int seq = (j['seq'] as num?)?.toInt() ?? -1;

    // seq 单调（只对强序帧）：旧的丢，跳号的补一次 sync 请求快照。
    if (seq >= 0 && kSeqFrames.contains(type)) {
      if (seq <= _lastSeq) {
        debugPrint('[YQK-ROOM] rx=$type seq=$seq 过期（last=$_lastSeq），丢弃');
        return;
      }
      if (_lastSeq >= 0 && seq > _lastSeq + 1) {
        debugPrint('[YQK-ROOM] gap expected=${_lastSeq + 1} got=$seq');
        send(<String, dynamic>{'type': 'sync', 'from': _lastSeq + 1});
      }
      _lastSeq = seq;
    }
    if (type == 'hello' || type == 'connected') {
      _memberId = (j['memberId'] as String?) ?? _memberId;
      _memberToken = (j['memberToken'] as String?) ?? _memberToken;
      // I-81：把 memberToken 落到 SecureStore（凭据不落 SharedPreferences）。
      // 进程被 force-stop 后重进房，握手带上同一个 token，服务端 memberByToken
      // 就能复用同一个 memberId，不会新增一条幽灵成员。
      unawaited(_persistMemberToken());
      if (type == 'hello') {
        final int resumeFrom = (j['resumeFrom'] as num?)?.toInt() ?? 0;
        // 首次进房（没进过 且 服务端说从 0 开始）才清历史；重连一律保留。
        // 「connected」帧不算：它的 resumeFrom 恒为 0，拿它判会把重连误清空。
        if (!_joinedOnce && resumeFrom <= 0) {
          _clearHistory();
          debugPrint('[YQK-ROOM] hello 首次进房 resumeFrom=$resumeFrom，历史清空');
        } else {
          debugPrint('[YQK-ROOM] hello 重连 resumeFrom=$resumeFrom，历史保留'
              ' chats=${_chats.value.length} danmakus=${_danmakus.value.length}');
        }
        _joinedOnce = true;
        // 进房成功后拉一次语音总开关（不进快照、不占 seq：这是本地 HTTP 端点）
        unawaited(_loadFeatures());
        // 点赞数：服务端快照是权威，重进房一律全量替换（本地乐观值作废）。
        final Object? rawLikes =
            (j['room'] is Map) ? (j['room'] as Map)['danmaku_likes'] : null;
        if (rawLikes is Map) {
          final Map<String, int> next = <String, int>{};
          rawLikes.forEach((Object? k, Object? v) {
            final String id = '$k';
            final int n = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
            if (id.isNotEmpty && n > 0) next[id] = n;
          });
          _danmakuLikes.value = next;
          debugPrint('[YQK-ROOM] hello danmaku_likes=${next.length} 条（全量替换）');
        }
      }
      // D21 房间回放：hello 的 danmakus 是服务端内存里的最近 N 条原始帧。
      // 按 id 去重（重连 / 重进房都走这里），再按 pos 排序交给渲染层 ——
      // 历史只能来自服务端 hello，本地绝不缓存副本（两条来源会打架）。
      final Object? rawHistory = j['danmakus'];
      if (rawHistory is List && rawHistory.isNotEmpty) {
        final Set<String> known = <String>{
          for (final RoomDanmaku d in _danmakuRing.toList()) d.id,
        };
        int added = 0;
        for (final Object? one in rawHistory) {
          if (one is! Map) continue;
          final RoomDanmaku d =
              RoomDanmaku.fromFrame(Map<String, dynamic>.from(one));
          if (d.id.isEmpty || !known.add(d.id)) continue;
          _danmakuRing.add(d);
          added++;
        }
        if (added > 0) {
          final List<RoomDanmaku> sorted = _danmakuRing.toList()
            ..sort((RoomDanmaku a, RoomDanmaku b) => a.pos.compareTo(b.pos));
          _danmakus.value = sorted;
        }
        debugPrint('[YQK-ROOM] hello danmakus=${_danmakus.value.length} 条'
            '（历史注入 added=$added）');
      }
      _setSnapshot(RoomSnapshot.fromHello(j));
    } else if (type == 'progress') {
      final String mid = (j['memberId'] as String?) ?? '';
      if (mid.isNotEmpty) {
        final Map<String, MemberProgress> next =
            Map<String, MemberProgress>.of(_progress.value);
        next[mid] = MemberProgress(
          position:
              Duration(milliseconds: (((j['position'] as num?)?.toDouble() ?? 0) * 1000).round()),
          playing: j['playing'] == true,
        );
        _progress.value = next;
      }
    } else if (type == 'state') {
      final Object? st = j['state'];
      if (st is Map) {
        final double pos = (st['position'] as num?)?.toDouble() ?? 0;
        final bool playing = st['playing'] == true;
        final double rate = (st['rate'] as num?)?.toDouble() ?? 1;
        // 基准时钟在这里起：用本地单调时钟，不用帧里的 updatedAt（跨设备时钟不同步）。
        _authBase = Duration(milliseconds: (pos * 1000).round());
        _authClock = Stopwatch()..start();
        _authPlaying = playing;
        _authRate = rate;
        _authBy = (st['by'] as String?) ?? _authBy;
        // 换片跟随：state 帧可能带 media（url）；没有就沿用上一次的
        final Object? media = st['media'];
        if (media is Map) {
          final String u = (media['url'] as String?) ?? '';
          if (u.isNotEmpty) _authMediaUrl = u;
        } else if (media is String && media.isNotEmpty) {
          _authMediaUrl = media;
        }
        _authoritative.value = _expectedNow();
        // 位置相等但播放态变了也要通知：靠 tick 递增，不依赖值比较
        _authTick.value = _authTick.value + 1;
        debugPrint('[YQK-ROOM] auth pos=$pos playing=$playing rate=$rate by=$_authBy');
      }
      final Object? room = j['room'];
      if (room is Map) {
        final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{'room': room});
        _setSnapshot(s);
      }
    } else if (type == 'settings') {
      // 切模式：出站复用 settings 帧（不新造帧名），只读 control_mode 字段
      final String mode = (j['control_mode'] as String?) ?? '';
      final RoomSnapshot? cur = _snapshot.value;
      if (cur != null && mode.isNotEmpty) {
        _setSnapshot(cur.withControlMode(mode));
      }
      debugPrint('[YQK-ROOM] settings control_mode=$mode');
    } else if (type == 'claim') {
      // 房主侧：有人请求控制权（帧名沿用 claim，pending/approve/reject 留给进房审批）
      _pending.value = j;
      debugPrint('[YQK-ROOM] claim rid=${j['rid']} action=${j['action']} ttl=${j['ttl']}');
    } else if (type == 'claim-result') {
      final bool ok = j['ok'] == true;
      if (ok) {
        _rejected.value = null;
        _claimGranted.value = _claimGranted.value + 1;
      } else {
        _rejected.value = j;
      }
      _pending.value = null;
      debugPrint('[YQK-ROOM] claim-result rid=${j['rid']} ok=$ok reason=${j['reason']}');
    } else if (type == 'muted') {
      // 禁言是强序帧：只改对应成员的 muted，重建一次快照（UI 走同一份只读投影）
      final String mid = (j['memberId'] as String?) ?? '';
      final bool muted = j['muted'] == true;
      final RoomSnapshot? cur = _snapshot.value;
      if (mid.isNotEmpty && cur != null) {
        _setSnapshot(cur.withMemberMuted(mid, muted));
      }
      debugPrint('[YQK-ROOM] muted memberId=$mid muted=$muted');
      _settleMuteWaiters(ok: true);
    } else if (type == 'error') {
      // 只在真有禁言请求在等时结算；其余错误帧照旧交给调用方日志
      if (_muteWaiters.isNotEmpty) {
        debugPrint('[YQK-ROOM] setMuted 被拒 code=${j['code']} message=${j['message']}');
        _settleMuteWaiters(ok: false);
      }
    } else if (type == 'control' || type == 'members') {
      final Object? room = j['room'];
      final Object? list = j['members'];
      if (room is Map) {
        final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{'room': room});
        _setSnapshot(s);
      } else if (list is List) {
        // 服务端 members 帧的形状是 {type, room:"CODE", members:[…], host?, seq}：
        // 只换成员表，其它字段沿用旧快照（禁言状态、房主变更都靠它到 UI）
        final RoomSnapshot? cur = _snapshot.value;
        final List<RoomMember> ms = <RoomMember>[
          for (final Object? one in list)
            if (one is Map) RoomMember.fromJson(Map<String, dynamic>.from(one)),
        ];
        if (cur != null) {
          _setSnapshot(cur.withMembers(ms, hostId: (j['host'] as String?) ?? ''));
        }
        debugPrint('[YQK-ROOM] $type members=${ms.length}');
      }
    } else if (type == 'joined' || type == 'left' || type == 'created' || type == 'mode') {
      // 有人进/出房、建房、切模式：帧里带 room 就就地更新，没带就向服务端要一次快照
      final Object? room = j['room'];
      if (room is Map) {
        final RoomSnapshot? s = RoomSnapshot.fromHello(<String, dynamic>{'room': room});
        if (s != null) {
          _setSnapshot(s);
          debugPrint('[YQK-ROOM] $type room members=${s.members.length}');
        }
      } else {
        debugPrint('[YQK-ROOM] $type 无 room，发 sync 要快照');
        send(<String, dynamic>{'type': 'sync'});
        // sync 回的是 state（不带成员表），成员条还得单独拉一次
        unawaited(_refreshMembers());
      }
    } else if (type == 'bot-state') {
      // D27：bot-state 带 seq，走的是上面同一道 seq 门（跳号会先 sync），
      // 这里只负责把全量快照落到 notifier 上。
      final BotState? bs = parseBotState(j);
      if (bs != null) {
        botState.value = bs;
        debugPrint('[YQK-BOT] state enabled=${bs.enabled} name=${bs.name} '
            'alias=${bs.aliases} mid=${bs.memberId}');
      }
    } else if (type == 'voice-state') {
      final VoiceState prev = _voiceState.value;
      // joined 用「我在不在 items 里」判断，不信服务端另发的布尔：
      // 服务端只发全量成员表，谁在表里谁就在语音里。
      final VoiceState next =
          parseVoiceState(j, me: memberId ?? '').copyWith(full: false);
      _voiceState.value = next;
      if (next.joined && !prev.joined) {
        debugPrint('[YQK-VOICE] join ok members=${next.items.length}');
      }
      if (prev.joined && !next.joined) {
        debugPrint('[YQK-VOICE] left members=${next.items.length}');
      }
      debugPrint('[YQK-VOICE] state members=${next.items.length} '
          'ids=${next.items.map((VoiceMember m) => m.id).join(",")}');
    } else if (type == 'voice-full') {
      final int max = (j['max'] as num?)?.toInt() ?? kVoiceMax;
      _voiceState.value = _voiceState.value.copyWith(full: true);
      voiceNotice.value = '语音房已满（最多 $max 人）';
      debugPrint('[YQK-VOICE] full 拒绝加入 members=${_voiceState.value.items.length}');
    } else if (type == 'voice-error') {
      final String code = (j['code'] as String?) ?? '';
      voiceNotice.value = code == 'no-room' ? '先进房间' : '语音不可用（$code）';
      debugPrint('[YQK-VOICE] error code=$code to=${j['to']}');
    } else if (type == 'offer' || type == 'sdp' || type == 'ice') {
      // 点对点信令单播帧：语音帧只有语音里的人才处理（没进语音时 engine 也没 PC）；
      // 屏幕共享帧（screen==true）不走语音，所以不要求在语音里。
      if (j['screen'] == true) {
        onP2P?.call(j);
      } else if (_voiceState.value.joined) {
        onP2P?.call(j);
      } else {
        debugPrint('[YQK-VOICE] drop p2p $type not-in-voice');
      }
    } else if (type == 'kicked') {
      // I-44：有人被房主移出。服务端已经把那条连接 close(4005)，本帧广播给其余人，
      // 成员条的更新仍以随后的 members 帧为准（不在这里本地删人）。
      final String kid = (j['id'] ?? '').toString();
      debugPrint('[YQK-ROOM] kicked id=$kid by=${j['by']}');
      if (kid == _memberId) {
        _kickNotice.value = '你已被房主移出房间';
        _setState(RoomClientState.closed);
        _transport?.close(1000, 'kicked');
      }
    } else if (type == 'media') {
      // 换片源：房主发起的整片切换。relay 会跳过发送者，所以房主自己不会收到；
      // 客人收到后交给 player_page 换成同一部片（不再回发）。
      final String from = (j['from'] as String?) ?? '';
      final String url = (j['url'] as String?) ?? '';
      if (url.isNotEmpty && from != _memberId) {
        debugPrint('[YQK-ROOM] rx=media url=$url title=${j['title']} from=$from');
        _mediaFrame.value = j;
      }
    } else if (type == 'web') {
      // D22：一起看网页。只负责把帧转给页面，业务判断（谁是房主、要不要跟随）留在页面里。
      debugPrint('[YQK-WEB] rx action=${j['action']} y=${j['y']} url=${j['url']}');
      _webEvents.add(j);
    } else if (type == 'chat') {
      final String fromId = (j['from'] ?? '').toString();
      if (fromId == _memberId) {
        // I-46：服务端把 chat/danmaku 回显给发送者，只为让 _lastSeq 跟上；
        // seq 已在上面推进过，这里只打一行日志、不再进列表（本地回显已经有了）。
        debugPrint('[YQK-ROOM] echo self chat id=${j['id']}');
      } else {
        final ChatMessage m = ChatMessage.fromFrame(j);
        _chatRing.add(m);
        _chats.value = _chatRing.toList();
        debugPrint('[YQK-ROOM] chat id=${m.id} from=${m.from} kind=${m.kind}');
      }
    } else if (type == 'chat-recall') {
      // 撤回：按 chatId 删一条，找不到就当没发生（不报错、不改列表）
      final String cid = (j['id'] as String?) ?? (j['chatId'] as String?) ?? '';
      if (cid.isNotEmpty && _chatRing.removeWhere((ChatMessage m) => m.id == cid)) {
        _chats.value = _chatRing.toList();
        debugPrint('[YQK-ROOM] chat-recall id=$cid removed');
      } else {
        debugPrint('[YQK-ROOM] chat-recall id=$cid 未命中，忽略');
      }
    } else if (type == 'danmaku') {
      final String fromId = (j['from'] ?? '').toString();
      if (fromId == _memberId) {
        debugPrint('[YQK-ROOM] echo self danmaku id=${j['id']}');
      } else {
        final RoomDanmaku m = RoomDanmaku.fromFrame(j);
        _danmakuRing.add(m);
        _danmakus.value = _danmakuRing.toList();
        debugPrint('[YQK-ROOM] danmaku id=${m.id} pos=${m.pos}');
      }
    } else if (type == 'danmaku-like' || type == 'danmaku-likes') {
      _applyDanmakuLikes(j, type);
    } else if (type == 'reaction') {
      final ReactionItem r = ReactionItem.fromFrame(j);
      _reactionRing.add(r);
      _reactions.value = _reactionRing.toList();
      debugPrint('[YQK-ROOM] reaction ${r.emoji} from=${r.id}');
    }
    debugPrint('[YQK-ROOM] rx=$type seq=$seq');
    if (!_frames.isClosed) _frames.add(j);
  }

  void _onClosed() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    // 断开后服务端已经把我们摘出语音（它自己广播了新全量），本地也清一份，
    // 免得重连前 UI 上还挂着「已加入」的麦克风
    _voiceState.value = VoiceState.empty;
    final int? code = _transport?.closeCode;
    _transport = null;
    if (_state == RoomClientState.closed || _state == RoomClientState.idle) return;

    // 被踢（4005）、token 无效（4001）、房间满（4004）都不重连。
    if (code == 4001 || code == 4004 || code == 4005) {
      debugPrint('[YQK-ROOM] closed code=$code，不重连');
      if (code == 4005) _kickNotice.value = '你已被房主移出房间';
      _setState(RoomClientState.closed);
      return;
    }
    _setState(RoomClientState.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _retry++;
    // 前 5 次指数退避（1/2/4/8/16s），之后固定 30s 一直试。
    // 原来 5 次就转 failed 永久停 —— 用户在地铁里断网两分钟回来，就再也连不上了，
    // 只能退出房间重进。房间是长连接场景，退避必须有上限、重试不能有终点。
    final int delaySec = _retry <= 5 ? (1 << (_retry - 1)).clamp(1, 16) : 30;
    if (_retry == 6) {
      debugPrint('[YQK-ROOM] 指数退避用尽，改为 30s 间隔继续重试（lastSeq=$_lastSeq）');
    }
    debugPrint('[YQK-ROOM] ${delaySec}s 后第 $_retry 次重连（lastSeq=$_lastSeq）');
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      unawaited(connect());
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      send(<String, dynamic>{'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch});
    });
  }

  // ── D26 健康检查 ────────────────────────────────────────────
  // 15 秒一次、3 秒超时、连续 3 次失败标 dead。本轮**只更新状态攒日志**，
  // 不做运行中自动切通道（下一轮再定切法）。
  Timer? _healthTimer;
  int _healthFail = 0;

  void _startHealth() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_probeHealth()),
    );
  }

  Future<void> _probeHealth() async {
    final Channel? ch = channel;
    final String base = ch?.baseUrl ?? baseUrl;
    final String id = ch?.id ?? 'lan';
    final Stopwatch sw = Stopwatch()..start();
    int code = 0;
    final HttpClient c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final HttpClientRequest req = await c
          .getUrl(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 3));
      final HttpClientResponse res =
          await req.close().timeout(const Duration(seconds: 3));
      code = res.statusCode;
      await res.drain<void>().timeout(const Duration(seconds: 3));
    } on Object {
      code = 0;
    } finally {
      c.close(force: true);
    }
    final int rtt = sw.elapsedMilliseconds;
    if (code == 200) {
      _healthFail = 0;
      if (ch != null) {
        ch.state = ChannelState.alive;
        ch.rttMs = rtt;
        ch.failCount = 0;
      }
      debugPrint('[YQK-CH] health id=$id ok=true rtt=${rtt}ms');
    } else {
      _healthFail++;
      final bool dead = _healthFail >= 3;
      if (ch != null) {
        ch.failCount = _healthFail;
        if (dead) ch.state = ChannelState.dead;
      }
      debugPrint('[YQK-CH] health id=$id ok=false '
          'fail=$_healthFail dead=$dead code=$code rtt=${rtt}ms');
    }
  }

  void _setState(RoomClientState s) {    if (_state == s) return;
    _state = s;
    debugPrint('[YQK-ROOM] state=${s.name}');
    if (!_states.isClosed) _states.add(s);
  }

  /// 正常收工：不再重连。
  Future<void> dispose() async {
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _healthTimer?.cancel();
    _coalesceTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _transport?.close(1000, 'bye');
    _transport = null;
    _setState(RoomClientState.closed);
    await _states.close();
    await _frames.close();
    botState.dispose();
    _kickNotice.dispose();
    unawaited(_webEvents.close());
  }
}

/// 真实传输：`dart:io` WebSocket。
Future<RoomTransport> _ioTransport(Uri uri) async {
  final WebSocket ws = await WebSocket.connect(uri.toString());
  return _IoWebSocketTransport(ws);
}

class _IoWebSocketTransport implements RoomTransport {
  _IoWebSocketTransport(this._ws);

  final WebSocket _ws;

  @override
  Stream<String> get messages =>
      _ws.map((dynamic e) => e is String ? e : utf8.decode(e as List<int>));

  @override
  int? get closeCode => _ws.closeCode;

  @override
  void send(String text) => _ws.add(text);

  @override
  Future<void> close([int code = 1000, String reason = '']) => _ws.close(code, reason);
}







/// `danmaku-likes` / `danmaku-like` 帧 → 与本地点赞表合并（**取 max，不覆盖**）。
///
/// 抽成纯函数是为了能在单测里直接验合并语义：
/// - `danmaku-likes` 的 `items`（服务端增量，可能一条或多条）
/// - 11 号文档 §8.2 的单条形状 `{"type":"danmaku-likes","id":..,"n":..}`（兼容）
/// - `danmaku-like`（别人的点赞转发帧，没有计数）→ 只当通知、不改计数（计数只认 danmaku-likes）
///
/// 只有真的变大才返回新表；没变化时返回入参本身（调用方用 identical 判等）。
Map<String, int> mergeDanmakuLikes(
    Map<String, int> current, Map<String, dynamic> j, String type) {
  final Map<String, int> next = <String, int>{...current};
  bool changed = false;

  void merge(String id, int n) {
    if (id.isEmpty) return;
    final int base = next[id] ?? 0;
    if (n > base) {
      next[id] = n;
      changed = true;
    }
  }

  if (type == 'danmaku-like') {
    // 计数一律以服务端 danmaku-likes 的权威值为准。
    // 服务端顺序是「先 broadcastRoom(danmaku-likes{items:{id:n}})，
    // 再 relay 本帧」，这里再 +1 会让所有非发送者永远多 1
    // （实测口径：探针点一次，手机侧会从 n 变 n+1）。
    // 本帧保留转发，只当「有人点赞」的通知，留给将来的点赞动效。
    return current;
  } else {
    final Object? items = j['items'];
    if (items is Map) {
      items.forEach((Object? k, Object? v) {
        merge('$k', (v is num) ? v.toInt() : int.tryParse('$v') ?? 0);
      });
    } else {
      final String did = (j['id'] as String?) ?? '';
      if (did.isNotEmpty) merge(did, (j['n'] as num?)?.toInt() ?? 0);
    }
  }
  return changed ? next : current;
}

/// hello 快照里的 `room.danmaku_likes` → 干净的 Map（重进房全量替换用）。
Map<String, int> parseDanmakuLikesSnapshot(Object? raw) {
  final Map<String, int> out = <String, int>{};
  if (raw is Map) {
    raw.forEach((Object? k, Object? v) {
      final String id = '$k';
      final int n = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      if (id.isNotEmpty && n > 0) out[id] = n;
    });
  }
  return out;
}
