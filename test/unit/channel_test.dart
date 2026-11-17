import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/platform/room/channel.dart';

Channel lan({int rtt = 5, int fail = 0, int kbps = 0, String id = 'lan'}) =>
    Channel(
      id: id,
      name: 'wlan0',
      host: '192.168.1.8',
      port: 8080,
      state: ChannelState.alive,
      rttMs: rtt,
      failCount: fail,
      kbps: kbps,
    );

Channel tun({int rtt = 40, int fail = 0, int kbps = 0}) => Channel(
      id: 'tunnel',
      name: '隧道',
      url: 'https://x.trycloudflare.com',
      state: ChannelState.alive,
      rttMs: rtt,
      failCount: fail,
      kbps: kbps,
    );

void main() {
  group('scoreChannel（15 号 D26 口径）', () {
    test('dead 通道沉底', () {
      final Channel d = lan(rtt: 1)..state = ChannelState.dead;
      expect(scoreChannel(d), -1 << 20);
      expect(scoreChannel(lan(rtt: 1)), greaterThan(scoreChannel(d)));
    });

    test('unknown 记 0，不冒充高分', () {
      final Channel u = lan()..state = ChannelState.unknown;
      expect(scoreChannel(u), 0);
    });

    test('rtt 低的分高（1000 - rtt*2）', () {
      expect(scoreChannel(lan(rtt: 10)), 980);
      expect(scoreChannel(lan(rtt: 100)), 800);
      expect(scoreChannel(lan(rtt: 10)),
          greaterThan(scoreChannel(lan(rtt: 100))));
    });

    test('failCount 每次扣 200', () {
      expect(scoreChannel(lan(rtt: 10, fail: 1)), 780);
      expect(scoreChannel(lan(rtt: 10, fail: 3)), 380);
    });

    test('kbps>=10000 才加 100 的 bonus；kbps 恒 0 时不加', () {
      expect(scoreChannel(lan(rtt: 10, kbps: 0)), 980);
      expect(scoreChannel(lan(rtt: 10, kbps: 12000)), 1080);
    });

    test('failCount 3 次的会被压到 rtt 差但没失败的通道下面', () {
      final Channel bad = lan(rtt: 1, fail: 3); // 1000-2-600=398
      final Channel ok = lan(rtt: 90); // 1000-180=820
      expect(scoreChannel(ok), greaterThan(scoreChannel(bad)));
    });
  });

  group('rankForMode', () {
    test('auto 全留且 rtt 低的在前', () {
      final Channel fast = lan(rtt: 5);
      final Channel slow = lan(rtt: 120);
      final List<Channel> r = rankForMode(<Channel>[slow, fast], ChannelMode.auto);
      expect(r.length, 2);
      expect(r.first.rttMs, 5);
    });

    test('auto 同分时 lan 排在 tunnel 前（固定顺序）', () {
      final Channel a = lan(rtt: 30); // 940
      final Channel b = tun(rtt: 30); // 940
      final List<Channel> r =
          rankForMode(<Channel>[b, a], ChannelMode.auto);
      expect(r.first.isTunnel, isFalse);
      expect(r.last.isTunnel, isTrue);
    });

    test('lanOnly 过滤掉 tunnel', () {
      final List<Channel> r = rankForMode(
        <Channel>[lan(), tun()],
        ChannelMode.lanOnly,
      );
      expect(r.length, 1);
      expect(r.single.id, 'lan');
    });

    test('forceTunnel 过滤掉 lan', () {
      final List<Channel> r = rankForMode(
        <Channel>[lan(), tun()],
        ChannelMode.forceTunnel,
      );
      expect(r.length, 1);
      expect(r.single.id, 'tunnel');
    });

    test('dead 排在活着的后面', () {
      final Channel dead = lan(rtt: 1)..state = ChannelState.dead;
      final Channel live = tun(rtt: 200);
      final List<Channel> r =
          rankForMode(<Channel>[dead, live], ChannelMode.auto);
      expect(r.first.isTunnel, isTrue);
      expect(r.last.state, ChannelState.dead);
    });
  });

  group('suggestQuality 三档边界', () {
    test('rtt=19 且带宽>20Mbps → 4K', () {
      expect(suggestQuality(lan(rtt: 19, kbps: 20001)), '4K');
    });

    test('rtt=20 → 1080P（4K 要求 <20）', () {
      expect(suggestQuality(lan(rtt: 20, kbps: 30000)), '1080P');
    });

    test('rtt=49 → 1080P', () {
      expect(suggestQuality(lan(rtt: 49)), '1080P');
    });

    test('rtt=50 → 720P', () {
      expect(suggestQuality(lan(rtt: 50)), '720P');
    });
  });

  group('parseChannels', () {
    test('lan 项要 host+port，tunnel 项要 url；缺字段跳过', () {
      final List<Channel> r = parseChannels(<Object?>[
        <String, Object?>{'id': 'lan', 'name': 'wlan0', 'host': '10.0.0.2', 'port': 8080},
        <String, Object?>{'id': 'tunnel', 'name': '隧道', 'url': 'https://a.b.c'},
        <String, Object?>{'id': 'lan', 'name': 'bad', 'host': '', 'port': 8080},
        <String, Object?>{'id': 'tunnel', 'name': 'bad'},
        'nonsense',
      ]);
      expect(r.length, 2);
      expect(r[0].baseUrl, 'http://10.0.0.2:8080');
      expect(r[1].baseUrl, 'https://a.b.c');
      expect(r[1].isTunnel, isTrue);
    });

    test('addrs 缺失/不是 List → 空表且不抛', () {
      expect(parseChannels(null), isEmpty);
      expect(parseChannels('oops'), isEmpty);
      expect(parseChannels(<Object?>[]), isEmpty);
    });
  });

  group('pref 序列化', () {
    test('round-trip', () {
      for (final ChannelMode m in ChannelMode.values) {
        expect(channelModeFromPref(channelModeToPref(m)), m);
      }
    });

    test('不认识的值按 auto', () {
      expect(channelModeFromPref(null), ChannelMode.auto);
      expect(channelModeFromPref(''), ChannelMode.auto);
      expect(channelModeFromPref('weird'), ChannelMode.auto);
    });
  });
}
