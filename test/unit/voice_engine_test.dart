import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCPeerConnection, RTCPeerConnectionState;
import 'package:yiqikan/platform/room/voice_engine.dart';

void main() {
  group('结束规则 canOffer（id 字典序大的一方发 offer）', () {
    test('大的一方发、小的一方不发', () {
      expect(canOffer('m_b', 'm_a'), isTrue);
      expect(canOffer('m_a', 'm_b'), isFalse);
      // 两端算出来必须相反，这是防 glare 的全部依据
      expect(canOffer('m_a', 'm_b') != canOffer('m_b', 'm_a'), isTrue);
    });

    test('相同 id / 空 id 一律不发', () {
      expect(canOffer('m_a', 'm_a'), isFalse);
      expect(canOffer('', 'm_a'), isFalse);
      expect(canOffer('m_a', ''), isFalse);
    });
  });

  group('ICE 三段式队列', () {
    test('上限 30：塞 35 条后只剩 30，且丢的是最旧的', () {
      final IceQueue q = IceQueue();
      for (int i = 1; i <= 35; i++) {
        q.push('p1', <String, dynamic>{'candidate': 'c$i'});
      }
      expect(q.queued('p1'), kIceQueueMax);
      final List<Map<String, dynamic>> all = q.drain('p1');
      expect(all.length, 30);
      // 最旧的 c1..c5 被丢，队首是 c6，队尾是 c35
      expect(all.first['candidate'], 'c6');
      expect(all.last['candidate'], 'c35');
    });

    test('超限时返回本次丢弃条数，未超限返回 0', () {
      final IceQueue q = IceQueue();
      for (int i = 1; i <= 30; i++) {
        expect(q.push('p1', <String, dynamic>{'candidate': 'c$i'}), 0);
      }
      expect(q.push('p1', <String, dynamic>{'candidate': 'c31'}), 1);
      expect(q.push('p1', <String, dynamic>{'candidate': 'c32'}), 1);
    });

    test('没有 remoteDescription 时全部入队，flush 后清空', () {
      final IceQueue q = IceQueue();
      q.push('peer', <String, dynamic>{'candidate': 'c1', 'sdpMid': '0', 'sdpMLineIndex': 0});
      q.push('peer', <String, dynamic>{'candidate': 'c2', 'sdpMid': '0', 'sdpMLineIndex': 0});
      q.push('peer', <String, dynamic>{'candidate': 'c3', 'sdpMid': '0', 'sdpMLineIndex': 0});
      expect(q.queued('peer'), 3);
      expect(q.total, 3);

      final List<Map<String, dynamic>> flush = q.drain('peer');
      expect(flush.map((Map<String, dynamic> c) => c['candidate']).toList(),
          <String>['c1', 'c2', 'c3']);
      // flush 之后必须干净，否则下次 setRemoteDescription 会重复 addCandidate
      expect(q.queued('peer'), 0);
      expect(q.total, 0);
      expect(q.drain('peer'), isEmpty);
    });

    test('每个 peer 独立计数，clear 清全部', () {
      final IceQueue q = IceQueue();
      q.push('a', <String, dynamic>{'candidate': 'x'});
      q.push('b', <String, dynamic>{'candidate': 'y'});
      q.push('b', <String, dynamic>{'candidate': 'z'});
      expect(q.queued('a'), 1);
      expect(q.queued('b'), 2);
      q.clear();
      expect(q.total, 0);
    });
  });

  group('并发建连与 stop 竞态（7b-2 修复）', () {
    test('同一 peer 并发 reconcile 两次，只建一条 PC', () async {
      int created = 0;
      final List<String> logs = <String>[];
      final VoiceEngine e = VoiceEngine(
        onSend: (Map<String, dynamic> _) {},
        onLog: logs.add,
        createPeer: () async {
          created++;
          return _FakePc();
        },
      );
      e.debugMarkStarted();
      final Future<void> a = e.reconcile(<String>['p']);
      final Future<void> b = e.reconcile(<String>['p']);
      await Future.wait(<Future<void>>[a, b]);
      expect(created, 1, reason: '并发两次只应触发一次 createPeerConnection');
      expect(e.pcCount, 1);
      expect(logs.where((String l) => l == 'pc create peer=p').length, 1);
    });

    test('stop 期间在途建连完成：不写回 _pcs，且抛 StateError 被吞', () async {
      final Completer<RTCPeerConnection> gate = Completer<RTCPeerConnection>();
      final List<String> logs = <String>[];
      final VoiceEngine e = VoiceEngine(
        onSend: (Map<String, dynamic> _) {},
        onLog: logs.add,
        createPeer: () => gate.future,
      );
      e.debugMarkStarted();
      final Future<void> inflight = e.reconcile(<String>['p']);
      await Future<void>.delayed(Duration.zero); // 让它停在 await createPeer 上
      final Future<void> stopping = e.stop(); // _started 立刻置 false
      gate.complete(_FakePc());
      await inflight;
      await stopping;
      expect(e.pcCount, 0, reason: 'stop 之后完成的 PC 不许写回 _pcs');
      expect(logs.where((String l) => l == 'pc create peer=p'), isEmpty);
      expect(logs.any((String l) => l == 'peer create fail peer=p StateError'), isTrue);
    });
  });

  group('12 秒建连超时降级（7b-3）', () {
    test('12 秒内 Connected → 计时器取消，没有 degrade', () async {
      final _CtlPc pc = _CtlPc();
      final List<String> logs = <String>[];
      int degraded = 0;
      final VoiceEngine e = VoiceEngine(
        onSend: (Map<String, dynamic> _) {},
        onLog: logs.add,
        createPeer: () async => pc,
        onConnectTimeout: (String peer, String state) => degraded++,
      );
      e.debugMarkStarted();
      await e.reconcile(<String>['p']);
      expect(e.debugTimerCount, 1, reason: '建完 PC 应该挂上一条计时器');
      pc.fire(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      expect(e.debugTimerCount, 0, reason: '连上后计时器必须取消');
      expect(degraded, 0);
      expect(logs.where((String l) => l.startsWith('degrade')).isEmpty, isTrue);
      expect(e.pcCount, 1);
      await e.stop();
    });

    test('12 秒仍没 Connected → degrade、PC 关闭、pcCount 归 0', () async {
      final _CtlPc pc = _CtlPc();
      final List<String> logs = <String>[];
      final List<String> degraded = <String>[];
      final VoiceEngine e = VoiceEngine(
        onSend: (Map<String, dynamic> _) {},
        onLog: logs.add,
        createPeer: () async => pc,
        onConnectTimeout: (String peer, String state) => degraded.add('$peer:$state'),
      );
      e.debugMarkStarted();
      await e.reconcile(<String>['p']);
      expect(e.pcCount, 1);
      // 计时器是 12 秒，等它真的到点（真实 Timer，不 mock）
      await Future<void>.delayed(VoiceEngine.kConnectTimeout + const Duration(seconds: 1));
      expect(degraded.length, 1);
      expect(degraded.single.split(':').first, 'p');
      expect(logs.any((String l) => l.startsWith('degrade peer=p 12s state=')), isTrue);
      expect(e.pcCount, 0, reason: '降级后 PC 必须已被关掉');
      expect(e.debugTimerCount, 0, reason: '降级后不许留计时器');
      await e.stop();
    });
  });
}

/// 只在单测里用的假 PC：所有成员（含 onIceCandidate 等 setter、close/addTrack）
/// 都走 noSuchMethod 返回 null，不碰真实 WebRTC。
class _FakePc implements RTCPeerConnection {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 可控连接状态的假 PC：能读出 connectionState，也能手动触发 onConnectionState 回调。
class _CtlPc implements RTCPeerConnection {
  RTCPeerConnectionState state = RTCPeerConnectionState.RTCPeerConnectionStateNew;
  void Function(RTCPeerConnectionState)? onState;

  void fire(RTCPeerConnectionState s) {
    state = s;
    onState?.call(s);
  }

  @override
  dynamic noSuchMethod(Invocation i) {
    final String name = i.memberName.toString();
    if (name == 'Symbol("onConnectionState=")') {
      onState = i.positionalArguments[0] as void Function(RTCPeerConnectionState)?;
      return null;
    }
    if (name == 'Symbol("connectionState")') return state;
    return null;
  }
}
