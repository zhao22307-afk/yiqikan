import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// D20 第二步：屏幕轨的点对点推送（只跑信令，不渲染）。
///
/// 房主侧 [start] 给每个客人建一条 PC、挂上屏幕视频轨、发 offer；
/// 客人侧拿 offer 走 [attachReceiver] 建接收用 PC、回 answer。
/// 两侧共用 [_pcs] 表，方向由调用点决定（发送方先 offer，接收方先 apply offer），
/// 所以 answer / ice 都能按 peer 回到正确的 PC 上。
///
/// 本轮不加 STUN/TURN：局域网直连，加了反而多一轮收集。
/// 也不做渲染、不做小窗：只保证 `onTrack` 真的被系统回调（V3 就是看那一行）。
class ScreenEngine {
  ScreenEngine({
    required this.onSend,
    this.onLog,
    this.onRemoteTrack,
  });

  /// 往房间发一条信令帧（offer / sdp / ice，都带 `screen: true`）。
  final void Function(Map<String, dynamic>)? onSend;

  /// 日志出口，页面上传 debugPrint，统一 `[YQK-SCREEN]` 前缀。
  final void Function(String)? onLog;

  /// 收到远端 track 时交给页面（客人侧画屏、房主侧不用）。
  final void Function(String peer, MediaStreamTrack t)? onRemoteTrack;

  final Map<String, RTCPeerConnection> _pcs = <String, RTCPeerConnection>{};

  /// 在途建连：同一 peer 的 offer 与 ice 并发到达时共用同一个 Future，
  /// 否则会建出两条 PC（voice_engine 第124行注释踩过同一个坑）。
  final Map<String, Future<RTCPeerConnection>> _creating =
      <String, Future<RTCPeerConnection>>{};

  /// 已经 setRemoteDescription 过的 peer：只有它们的 candidate 能立刻 add，
  /// 其余先入队（远端 candidate 常常比 answer/offer 先到）。
  final Set<String> _haveRemote = <String>{};
  final Map<String, List<Map<String, dynamic>>> _pending =
      <String, List<Map<String, dynamic>>>{};

  MediaStreamTrack? _track;

  /// D20 音频（第49轮）：Android 侧 getDisplayMedia 通常不给音轨，这里默认为空。
  List<MediaStreamTrack> _audio = const <MediaStreamTrack>[];

  bool get active => _track != null;

  int get pcCount => _pcs.length;

  void _log(String line) => onLog?.call(line);

  void _send(Map<String, dynamic> f) => onSend?.call(f);

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
    // 与语音一致：空 iceServers，只走本机收集的 host candidate。
    _log('[YQK-SCREEN] create-pc peer=$peer begin');
    final RTCPeerConnection pc =
        await createPeerConnection(<String, dynamic>{'iceServers': <Object>[]});
    _log('[YQK-SCREEN] create-pc peer=$peer done');
    _pcs[peer] = pc;
    _haveRemote.remove(peer);

    pc.onIceCandidate = (RTCIceCandidate c) {
      final String? cand = c.candidate;
      if (cand == null || cand.isEmpty) return;
      _send(<String, dynamic>{
        'type': 'ice',
        'to': peer,
        'screen': true,
        'candidate': <String, dynamic>{
          'candidate': cand,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };
    pc.onIceConnectionState = (RTCIceConnectionState s) =>
        _log('[YQK-SCREEN] pc $peer ice=$s cs=${pc.connectionState}');
    pc.onConnectionState = (RTCPeerConnectionState s) =>
        _log('[YQK-SCREEN] pc $peer ice=${pc.iceConnectionState} cs=$s');
    pc.onTrack = (RTCTrackEvent e) {
      _log('[YQK-SCREEN] remote track peer=$peer kind=${e.track.kind} '
          'id=${e.track.id} streams=${e.streams.length}');
      if (e.track.kind == 'video') {
        onRemoteTrack?.call(peer, e.track);
      } else {
        _log('[YQK-SCREEN] remote audio peer=$peer id=${e.track.id}');
      }
    };

    final MediaStreamTrack? t = _track;
    if (t != null) {
      _log('[YQK-SCREEN] addTrack begin peer=$peer');
      try {
        await pc.addTransceiver(
          track: t,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
          ),
        );
        _log('[YQK-SCREEN] addTrack done peer=$peer');
      } catch (e) {
        _log('[YQK-SCREEN] addTrack fail peer=$peer ${e.runtimeType}');
      }
    }
    for (final MediaStreamTrack a in _audio) {
      try {
        await pc.addTransceiver(
          track: a,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
          ),
        );
        _log('[YQK-SCREEN] addAudio done peer=$peer id=${a.id}');
      } catch (e) {
        _log('[YQK-SCREEN] addAudio fail peer=$peer ${e.runtimeType}');
      }
    }
    _log('[YQK-SCREEN] pc $peer create');
    return pc;
  }

  /// 房主侧：给每个客人建 PC 并发 offer。
  Future<void> start(
    MediaStreamTrack track,
    List<String> peers, {
    List<MediaStreamTrack> audioTracks = const <MediaStreamTrack>[],
  }) async {
    _track = track;
    _audio = audioTracks;
    _log('[YQK-SCREEN] start peers=${peers.length} track=${track.id} '
        'audio=${_audio.length}');
    for (final String peer in peers) {
      if (peer.isEmpty) continue;
      try {
        final RTCPeerConnection pc = await _newPeer(peer);
        _log('[YQK-SCREEN] offer begin peer=$peer');
        final RTCSessionDescription offer = await pc.createOffer();
        _log('[YQK-SCREEN] offer built peer=$peer len=${offer.sdp?.length ?? 0}');
        await pc.setLocalDescription(offer);
        _send(<String, dynamic>{
          'type': 'offer',
          'to': peer,
          'screen': true,
          'sdp': offer.sdp ?? '',
        });
        _log('[YQK-SCREEN] offer send peer=$peer');
      } catch (e) {
        _log('[YQK-SCREEN] offer send fail peer=$peer ${e.runtimeType}');
      }
    }
  }

  /// 客人侧：收到 offer 后建 PC、回 answer。`peer` 是房主的 memberId。
  Future<void> attachReceiver(String peer, String sdp) async {
    if (peer.isEmpty) return;
    final RTCPeerConnection pc = await _newPeer(peer);
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _haveRemote.add(peer);
      await _flushIce(peer);
      final RTCSessionDescription ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      _send(<String, dynamic>{
        'type': 'sdp',
        'to': peer,
        'screen': true,
        'sdp': ans.sdp ?? '',
      });
      _log('[YQK-SCREEN] answer send peer=$peer');
    } catch (e) {
      // SDP 不合法也不崩：等下一次共享重来。
      _log('[YQK-SCREEN] offer apply fail peer=$peer ${e.runtimeType}');
    }
  }

  /// offer / sdp / ice 统一入口（两段逻辑共用，靠帧内容区分方向）。
  Future<void> onSignal(Map<String, dynamic> f) async {
    final String type = (f['type'] as String?) ?? '';
    final String peer = (f['from'] as String?) ?? '';
    if (peer.isEmpty) return _log('[YQK-SCREEN] signal drop no-from type=$type');
    if (type == 'offer') {
      return attachReceiver(peer, (f['sdp'] as String?) ?? '');
    }
    if (type == 'sdp') return _onAnswer(peer, (f['sdp'] as String?) ?? '');
    if (type == 'ice') return _onIce(peer, f);
    _log('[YQK-SCREEN] signal ignore type=$type');
  }

  Future<void> _onAnswer(String peer, String sdp) async {
    final RTCPeerConnection? pc = _pcs[peer];
    if (pc == null) return _log('[YQK-SCREEN] answer drop no-pc peer=$peer');
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      _haveRemote.add(peer);
      await _flushIce(peer);
      _log('[YQK-SCREEN] answer apply ok peer=$peer');
    } catch (e) {
      _log('[YQK-SCREEN] answer apply fail peer=$peer ${e.runtimeType}');
    }
  }

  Future<void> _onIce(String peer, Map<String, dynamic> f) async {
    if (!_pcs.containsKey(peer)) {
      return _log('[YQK-SCREEN] ice drop no-pc peer=$peer');
    }
    final Object? raw = f['candidate'];
    final Map<String, dynamic>? cand = raw is Map
        ? <String, dynamic>{
            'candidate': raw['candidate'],
            'sdpMid': raw['sdpMid'],
            'sdpMLineIndex': raw['sdpMLineIndex'],
          }
        : (raw is String && raw.isNotEmpty
            ? <String, dynamic>{
                'candidate': raw,
                'sdpMid': f['sdpMid'] ?? '0',
                'sdpMLineIndex': f['sdpMLineIndex'] ?? 0,
              }
            : null);
    if (cand == null) return _log('[YQK-SCREEN] ice drop bad peer=$peer');
    if (!_haveRemote.contains(peer)) {
      (_pending[peer] ??= <Map<String, dynamic>>[]).add(cand);
      _log('[YQK-SCREEN] ice queued peer=$peer n=${_pending[peer]!.length}');
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
      _log('[YQK-SCREEN] addCandidate fail peer=$peer ${e.runtimeType}');
    }
  }

  Future<void> _flushIce(String peer) async {
    final List<Map<String, dynamic>> list =
        _pending.remove(peer) ?? <Map<String, dynamic>>[];
    for (final Map<String, dynamic> c in list) {
      await _addCandidate(peer, c);
    }
    if (list.isNotEmpty) _log('[YQK-SCREEN] ice flush peer=$peer n=${list.length}');
  }

  /// 关掉全部 PC。本地 track 由 ScreenShare 负责 stop，这里只丢引用。
  Future<void> stop() async {
    final int n = _pcs.length;
    for (final String peer in _pcs.keys.toList()) {
      final RTCPeerConnection? pc = _pcs.remove(peer);
      if (pc != null) {
        try {
          await pc.close();
        } catch (e) {
          _log('[YQK-SCREEN] pc close fail peer=$peer ${e.runtimeType}');
        }
      }
      _log('[YQK-SCREEN] pc $peer close');
    }
    _track = null;
    _audio = const <MediaStreamTrack>[];
    _creating.clear();
    _pending.clear();
    _haveRemote.clear();
    _log('[YQK-SCREEN] pc=$n close');
  }
}
