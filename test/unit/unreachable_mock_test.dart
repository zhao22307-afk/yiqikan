import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/data/parsers/bilibili.dart';
import 'package:yiqikan/domain/resolver.dart';

/// 模拟「一条永远返回 bilibili:// 且没有音频轨」的解析档位（原 App 的 B 站接口偶发这么回）
class _FakeBiliAudioStage implements ResolveStage {
  int calls = 0;

  @override
  String get name => 'B 站';

  @override
  Future<ResolvedUrl?> tryResolve(String url) async {
    calls++;
    return ResolvedUrl(
      url: 'bilibili://video/1',
      audioUrl: null,
      expiresAt: DateTime.now().add(Resolver.bilibiliUrlTtl),
      lastUrlUpdate: DateTime.now(),
      resolver: 'bilibili',
    );
  }
}

/// 第一次抛 -10403（地区限制），之后统计调用次数
class _RegionLockedClient extends BilibiliClient {
  _RegionLockedClient() : super(dio: Dio());

  int calls = 0;

  @override
  Future<PgcSeason> pgcSeason({int? epId, int? seasonId}) async {
    calls++;
    throw const RegionLockedException();
  }
}

void main() {
  test('bilibili:// 且 audioUrl 为空 → 第二次解析会重新请求上游', () async {
    final _FakeBiliAudioStage stage = _FakeBiliAudioStage();
    final Resolver resolver = Resolver(stages: <ResolveStage>[stage]);

    await resolver.resolve('https://www.bilibili.com/video/BV1xx411c7mD');
    expect(stage.calls, 1);

    final ResolvedUrl second =
        await resolver.resolve('https://www.bilibili.com/video/BV1xx411c7mD');
    expect(second.url, 'bilibili://video/1');
    // 关键断点：没有 audioUrl 的 bilibili:// 链接不许被当成「新鲜缓存」直接用
    expect(stage.calls, 2);
  });

  test('-10403：第一次打请求并写标记，第二次不发请求直接抛', () async {
    bool blocked = false;
    int markCount = 0;
    final _RegionLockedClient client = _RegionLockedClient();
    final Resolver resolver = Resolver(
      stages: <ResolveStage>[
        BilibiliStage(
          client: client,
          isBlocked: () async => blocked,
          onBlocked: () async {
            markCount++;
            blocked = true;
          },
        ),
      ],
    );

    await expectLater(
      resolver.resolve('https://www.bilibili.com/bangumi/play/ep826497'),
      throwsA(isA<ResolveFailedException>()),
    );
    expect(client.calls, 1);
    expect(markCount, 1);
    expect(blocked, isTrue);

    await expectLater(
      resolver.resolve('https://www.bilibili.com/bangumi/play/ep826497'),
      throwsA(isA<ResolveFailedException>()),
    );
    // 第二次：命中 blocked 后直接抛，没有再打接口
    expect(client.calls, 1);
    expect(markCount, 1);
  });
}
