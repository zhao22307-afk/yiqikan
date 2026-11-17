import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/data/parsers/bilibili.dart';
import 'package:yiqikan/domain/resolver.dart';

void main() {
  group('ResolvedUrl 四条刷新判据（原 App needsRefresh）', () {
    ResolvedUrl make({
      String url = 'https://cdn.example.com/a.m4s?x=1',
      DateTime? expiresAt,
      String? audioUrl = 'https://cdn.example.com/a-ac.m4s',
    }) {
      return ResolvedUrl(
        url: url,
        expiresAt: expiresAt,
        audioUrl: audioUrl,
        lastUrlUpdate: DateTime.now(),
        resolver: 'bilibili',
      );
    }

    test('直链为空 → 刷新', () {
      final ResolvedUrl r = make(url: '  ');
      expect(r.needsRefresh, isTrue);
      expect(r.refreshReason, '直链为空');
    });

    test('bilibili:// 但 audioUrl 为空 → 刷新', () {
      final ResolvedUrl r =
          make(url: 'bilibili://video/1', audioUrl: null);
      expect(r.needsRefresh, isTrue);
      expect(r.refreshReason, 'bilibili://链接但audioUrl为空');
    });

    test('还剩不到 10 分钟 → 刷新（last_url_update 太久）', () {
      final ResolvedUrl r = make(
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      );
      expect(r.needsRefresh, isTrue);
      expect(r.refreshReason, contains('last_url_update超过 10 分钟'));
    });

    test('已过期 → 刷新', () {
      final ResolvedUrl r = make(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(r.refreshReason, '已过期');
    });

    test('刚拿到（90 分钟）→ 不刷新', () {
      final ResolvedUrl r =
          make(expiresAt: DateTime.now().add(Resolver.bilibiliUrlTtl));
      expect(r.needsRefresh, isFalse);
      expect(Resolver.bilibiliUrlTtl, const Duration(minutes: 90));
    });
  });

  group('B 站不可恢复失败要停刷新', () {
    test('已标记 unreachable → 直接抛，不发请求', () async {
      final BilibiliStage stage = BilibiliStage(
        isBlocked: () async => true,
        onBlocked: () async {},
      );
      await expectLater(
        stage.tryResolve('https://www.bilibili.com/video/BV1xx411c7mD'),
        throwsA(isA<RegionLockedException>()),
      );
    });

    test('命中版权/会员限制 → 写标记', () async {
      bool marked = false;
      final BilibiliStage stage = BilibiliStage(
        client: _LockedClient(),
        isBlocked: () async => false,
        onBlocked: () async => marked = true,
      );
      await expectLater(
        stage.tryResolve('https://www.bilibili.com/bangumi/play/ep123'),
        throwsA(isA<ContentLockedException>()),
      );
      expect(marked, isTrue);
    });
  });

  group('番剧 episodes 过滤预告并按 ep_id 对齐', () {
    test('跳过预告/PV/花絮，保留正片', () {
      final List<Object?> raw = <Object?>[
        <String, Object?>{'id': 1, 'cid': 101, 'title': '第1话', 'badge': ''},
        <String, Object?>{
          'id': 2,
          'cid': 0,
          'title': '第2话',
          'badge': '预告',
        },
        <String, Object?>{'id': 3, 'cid': 103, 'title': 'PV1', 'badge': ''},
        <String, Object?>{'id': 4, 'cid': 104, 'title': '花絮1', 'badge': ''},
        <String, Object?>{'id': 5, 'cid': 105, 'title': '第2话', 'badge': ''},
      ];
      final List<String> skipped = <String>[];
      final List<PgcEpisode> eps = BilibiliClient.parsePgcEpisodes(
        raw,
        onSkip: skipped.add,
      );
      expect(eps.map((PgcEpisode e) => e.epId).toList(), <int>[1, 5]);
      expect(eps.map((PgcEpisode e) => e.cid).toList(), <int>[101, 105]);
      expect(skipped.length, 3);
    });

    test('ep_id 映射不会因为中间被过滤而错位', () {
      const PgcSeason season = PgcSeason(
        seasonId: 1,
        title: 't',
        cover: '',
        episodes: <PgcEpisode>[
          PgcEpisode(epId: 11, cid: 111, bvid: '', title: '第1话'),
          PgcEpisode(epId: 13, cid: 113, bvid: '', title: '第2话'),
        ],
      );
      expect(season.byEpId(13)?.cid, 113);
      expect(season.episodeMap[11]?.cid, 111);
      expect(season.byEpId(12), isNull);
    });
  });
}

/// 模拟「这条是大会员/版权限制」的客户端
class _LockedClient extends BilibiliClient {
  _LockedClient();

  @override
  Future<PgcSeason> pgcSeason({int? epId, int? seasonId}) async {
    throw const ContentLockedException();
  }
}
