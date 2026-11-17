import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// 结束规则：成员 id 字典序**大**的一方发 offer，小的只应答。
/// 两人几乎同时进语音时「后进者发」在两端看到的顺序可能不同（glare）；
/// id 定序是确定性的，两端算出来必然相反，不需要协商。
bool canOffer(String myId, String peerId) =>
    myId.isNotEmpty && peerId.isNotEmpty && myId.compareTo(peerId) > 0;

/// 每个 peer 最多攒多少条 ICE。
const int kIceQueueMax = 30;

/// ICE 三段式队列（纯数据，不碰 WebRTC，单测可直接构造）。
class IceQueue {
  final Map<String, List<Map<String, dynamic>>> _q = <String, List<Map<String, dynamic>>>{};

  int queued(String peer) => _q[peer]?.length ?? 0;

  int get total {
    int n = 0;
    for (final List<Map<String, dynamic>> v in _q.values) {
      n += v.length;
    }
    return n;
  }

  /// 入队，返回「本次因超限被丢掉的条数」（0 表示没丢）。
  int push(String peer, Map<String, dynamic> cand) {
    final List<Map<String, dynamic>> list = _q.putIfAbsent(peer, () => <Map<String, dynamic>>[]);
    list.add(cand);
    if (list.length <= kIceQueueMax) return 0;
    final int dropped = list.length - kIceQueueMax;
    list.removeRange(0, dropped); // 丢最旧的
    return dropped;
  }

  List<Map<String, dynamic>> drain(String peer) =>
      _q.remove(peer) ?? <Map<String, dynamic>>[];

  void clear() => _q.clear();
}

/// 一个 VoiceEngine 管 N 条 RTCPeerConnection（Mesh：n 人 = n-1 条）。
/// 7b-1 只做媒体栈骨架：采集 + 单端建连 + ICE 三段式 + 失败不崩；
/// 远端音轨不播放（7b-2 接听感），onTrack 只打日志。
class VoiceEngine {
  VoiceEngine({
    required this.onSend,
    required this.onLog,
    Future<RTCPeerConnection> Function()? createPeer,
    this.onConnectTimeout,
  }) : _createPeerFn = createPeer ?? _defaultCreatePeer;

  /// 23 §4 第 8 条：12 秒没连上就降级（退出语音），不许干挂着等。
  /// 固定值，不做成可配置——调大调小都要重新验收。
  static const Duration kConnectTimeout = Duration(seconds: 12);

  /// 降级回调：engine 自己已经关掉这条 PC，页面只负责提示 + 退出语音。
  final void Function(String peer, String state)? onConnectTimeout;

  /// 每条 peer 的建连计时器；_closePeer 与 stop 两处都必须 cancel，
  /// 否则进进出出会攒一堆 Timer（上一轮 addListener 的账）。
  final Map<String, Timer> _timeouts = <String, Timer>{};

  /// 建连函数可注入：单测里换成 Completer 控制的假 PC，
  /// 才能验证「并发只建一条」「stop 期间完成不写回」这两条竞态。
  final Future<RTCPeerConnection> Function() _createPeerFn;

  static Future<RTCPeerConnection> _defaultCreatePeer() => createPeerConnection(<String, dynamic>{
        'iceServers': <Map<String, dynamic>>[<String, dynamic>{'urls': 'stun:stun.l.google.com:19302'}],
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
      });

  final void Function(Map<String, dynamic> frame) onSend;
  final void Function(String line) onLog;
  final Map<String, RTCPeerConnection> _pcs = <String, RTCPeerConnection>{};
  final IceQueue _pending = IceQueue();
  final Set<String> _haveRemote = <String>{};
  MediaStream? _local;
  String _myId = '';
  bool _started = false;

  /// 单测用：跳过 start()（它会申请麦克风权限），直接进入可 reconcile 状态。
  void debugMarkStarted() {
    _started = true;
  }

  int get pcCount => _pcs.length;
  bool get started => _started;

  /// 单测用：看还有几条建连计时器挂着（正常路径连上后必须是 0）。
  int get debugTimerCount => _timeouts.length;

  /// 申请麦克风权限 + 采集本地音轨；失败返回 false（调用方不许再发 join）。
  Future<bool> start(String myId) async {
    _myId = myId;
    if (_started) return true;
    PermissionStatus st = await Permission.microphone.status;
    if (!st.isGranted) st = await Permission.microphone.request();
    if (!st.isGranted) {
      onLog('mic denied');
      return false;
    }
    onLog('mic granted');
    try {
      _local = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': <String, dynamic>{'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': false,
      });
      _started = true;
      onLog('media local track ok tracks=${_local!.getAudioTracks().length}');
      return true;
    } catch (e) {
      onLog('media local track fail ${e.runtimeType}');
      _local = null;
      return false;
    }
  }

  /// reconcile 的串行队列：并发进来的调用只排队，不交叉执行，
  /// 否则两帧 state 一前一后会同时走到 _newPeer，同一 peer 建两条 PC。
  Future<void> _reconcileChain = Future<void>.value();

  /// 按语音成员表建/拆连接。peers 里不含自己。
  Future<void> reconcile(List<String> peers) {
    final List<String> snapshot = List<String>.of(peers);
    final Future<void> next = _reconcileChain.then((_) => _reconcileInner(snapshot));
    _reconcileChain = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _reconcileInner(List<String> peers) async {
    if (!_started) {
      onLog('reconcile skip not-started');
      return;
    }
    for (final String p in _pcs.keys.toList()) {
      if (!peers.contains(p)) await _closePeer(p);
    }
    for (final String p in peers) {
      if (_pcs.containsKey(p)) continue;
      try {
        await _newPeer(p);
        if (canOffer(_myId, p)) {
          await _sendOffer(p);
        } else {
          onLog('pc wait offer peer=$p');
        }
      } catch (e) {
        onLog('peer create fail peer=$p ${e.runtimeType}');
      }
    }
    onLog('pc count=${_pcs.length}');
  }

  /// 在途建连表：同一 peer 的多次并发请求共用同一个 Future，
  /// 避免 `await createPeerConnection` 期间的空窗被第二次调用穿过去。
  final Map<String, Future<RTCPeerConnection>> _creating = <String, Future<RTCPeerConnection>>{};

  Future<RTCPeerConnection> _newPeer(String peer) {
    final Future<RTCPeerConnection>? inflight = _creating[peer];
    if (inflight != null) return inflight;
    final Future<RTCPeerConnection> f = _createPeer(peer);
    _creating[peer] = f;
    return f.whenComplete(() {
      _creating.remove(peer);
    });
  }

  Future<RTCPeerConnection> _createPeer(String peer) async {
    final RTCPeerConnection pc = await _createPeerFn();
    // 建连期间可能已经 stop()：此时不能把 PC 塞回 _pcs，否则它会漏关。
    if (!_started) {
      try {
        await pc.close();
      } catch (_) {}
      throw StateError('engine stopped');
    }
    _pcs[peer] = pc;
    _haveRemote.remove(peer);
    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      onSend(<String, dynamic>{
        'type': 'ice',
        'to': peer,
        'candidate': <String, dynamic>{'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
      });
    };
    pc.onIceConnectionState = (RTCIceConnectionState s) => onLog('ice state peer=$peer $s');
    pc.onConnectionState = (RTCPeerConnectionState s) {
      onLog('pc state peer=$peer $s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _timeouts.remove(peer)?.cancel();
      }
    };
    // 建连计时：从建 PC 起算 12 秒，到点还没 Connected 就降级。
    _timeouts.remove(peer)?.cancel();
    _timeouts[peer] = Timer(kConnectTimeout, () {
      _timeouts.remove(peer);
      final RTCPeerConnection? live = _pcs[peer];
      final RTCPeerConnectionState? now = live?.connectionState;
      if (now == RTCPeerConnectionState.RTCPeerConnectionStateConnected) return;
      onLog('degrade peer=$peer 12s state=$now');
      unawaited(_closePeer(peer));
      onConnectTimeout?.call(peer, '$now');
    });
    // 7b-1 不播放远端音频：只确认轨道真的到了。
    pc.onTrack = (RTCTrackEvent e) => onLog('remote track peer=$peer kind=${e.track.kind}');
    final MediaStream? local = _local;
    if (local != null) {
      for (final MediaStreamTrack t in local.getAudioTracks()) {
        await pc.addTrack(t, local);
      }
    }
    onLog('pc create peer=$peer');
    return pc;
  }

  Future<void> _sendOffer(String peer) async {
    final RTCPeerConnection? pc = _pcs[peer];
    if (pc == null) return;
    try {
      final RTCSessionDescription offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      onSend(<String, dynamic>{'type': 'offer', 'to': peer, 'sdp': offer.sdp ?? ''});
      onLog('offer send peer=$peer');
    } catch (e) {
      onLog('offer send fail peer=$peer ${e.runtimeType}');
    }
  }

  /// offer / sdp / ice 三类入口。f 是服务端原帧（带 from / to）。
  Future<void> onSignal(Map<String, dynamic> f) async {
    final String type = (f['type'] as String?) ?? '';
    final String peer = (f['from'] as String?) ?? '';
    if (peer.isEmpty) return onLog('signal drop no-from type=$type');
    if (!_started) return onLog('signal drop not-started type=$type');
    if (type == 'ice') return _onIce(peer, f);
    if (type == 'offer') return _onOffer(peer, (f['sdp'] as String?) ?? '');
    if (type == 'sdp') return _onAnswer(peer, (f['sdp'] as String?) ?? '');
  }

  Future<void> _onOffer(String peer, String sdp) async {
    final RTCPeerConnection pc = _pcs[peer] ?? await _newPeer(peer);
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _haveRemote.add(peer);
      await _flushIce(peer);
      final RTCSessionDescription ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      onSend(<String, dynamic>{'type': 'sdp', 'to': peer, 'sdp': ans.sdp ?? '', 'type_': 'answer'});
      onLog('answer send peer=$peer');
    } catch (e) {
      // 对端 SDP 不合法：不崩、不退出语音，等下一次 reconcile。
      onLog('offer apply fail peer=$peer ${e.runtimeType}');
    }
  }

  Future<void> _onAnswer(String peer, String sdp) async {
    final RTCPeerConnection? pc = _pcs[peer];
    if (pc == null) return onLog('answer drop no-pc peer=$peer');
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      _haveRemote.add(peer);
      await _flushIce(peer);
      onLog('answer apply ok peer=$peer');
    } catch (e) {
      // 假 SDP / 顺序错都走这里：进程不退出，语音成员表照旧。
      onLog('answer apply fail ${e.runtimeType}');
    }
  }

  /// 三段式：不在语音 → 丢；没 PC / 没 remoteDescription → 入队；否则立即加。
  Future<void> _onIce(String peer, Map<String, dynamic> f) async {
    if (!_pcs.containsKey(peer)) return onLog('ice drop not-in-voice peer=$peer');
    final Object? raw = f['candidate'];
    final Map<String, dynamic>? cand = raw is Map
        ? <String, dynamic>{'candidate': raw['candidate'], 'sdpMid': raw['sdpMid'], 'sdpMLineIndex': raw['sdpMLineIndex']}
        : (raw is String && raw.isNotEmpty
            ? <String, dynamic>{'candidate': raw, 'sdpMid': f['sdpMid'] ?? '0', 'sdpMLineIndex': f['sdpMLineIndex'] ?? 0}
            : null);
    if (cand == null) return onLog('ice drop bad-candidate peer=$peer');
    if (!_haveRemote.contains(peer)) {
      final int dropped = _pending.push(peer, cand);
      if (dropped > 0) onLog('ice overflow peer=$peer dropped=$dropped');
      onLog('ice queued peer=$peer n=${_pending.queued(peer)}');
      return;
    }
    await _addCandidate(peer, cand);
  }

  Future<void> _addCandidate(String peer, Map<String, dynamic> cand) async {
    final RTCPeerConnection? pc = _pcs[peer];
    if (pc == null) return;
    try {
      await pc.addCandidate(RTCIceCandidate(
        cand['candidate'] as String?,
        cand['sdpMid'] as String?,
        (cand['sdpMLineIndex'] as num?)?.toInt(),
      ));
    } catch (e) {
      onLog('addCandidate fail peer=$peer ${e.runtimeType}');
    }
  }

  Future<void> _flushIce(String peer) async {
    final List<Map<String, dynamic>> list = _pending.drain(peer);
    if (list.isEmpty) return;
    for (final Map<String, dynamic> c in list) {
      await _addCandidate(peer, c);
    }
    onLog('ice flush peer=$peer n=${list.length}');
  }

  Future<void> _closePeer(String peer) async {
    _timeouts.remove(peer)?.cancel();
    final RTCPeerConnection? pc = _pcs.remove(peer);
    _haveRemote.remove(peer);
    _pending.drain(peer);
    if (pc != null) {
      try {
        await pc.close();
      } catch (e) {
        onLog('pc close fail peer=$peer ${e.runtimeType}');
      }
    }
    onLog('pc close peer=$peer');
  }

  /// 释放所有 PC 与本地轨道；重复调用安全。
  Future<void> stop() async {
    _started = false;
    final int n = _pcs.length;
    for (final String p in _pcs.keys.toList()) {
      await _closePeer(p);
    }
    _creating.clear();
    for (final Timer t in _timeouts.values) {
      t.cancel();
    }
    _timeouts.clear();
    _pending.clear();
    _haveRemote.clear();
    final MediaStream? local = _local;
    _local = null;
    if (local != null) {
      try {
        for (final MediaStreamTrack t in local.getTracks()) {
          await t.stop();
        }
        await local.dispose();
      } catch (e) {
        onLog('local dispose fail ${e.runtimeType}');
      }
    }
    onLog('engine disposed pc=$n');
  }
}
