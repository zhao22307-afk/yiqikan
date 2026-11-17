import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/resolver.dart';

/// 假的一档：认识任何 http 链接，命中次数自己数
class _CountingStage extends ResolveStage {
  int hits = 0;

  @override
  String get name => '假档';

  @override
  Future<ResolvedUrl?> tryResolve(String url) async {
    hits++;
    return ResolvedUrl(
      url: 'https://cdn.example.com/video.m3u8?sig=$hits',
      resolver: 'fake',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

void main() {
  test('B19 同一 URL 连解两次只打一次上游', () async {
    final _CountingStage stage = _CountingStage();
    final Resolver r = Resolver(stages: <ResolveStage>[stage]);

    final ResolvedUrl a = await r.resolve('https://x.com/p?b=2&a=1');
    final ResolvedUrl b = await r.resolve('https://x.com/p?b=2&a=1');
    // ignore: avoid_print
    print('[cache] 第一次=${a.url} 第二次=${b.url} 上游命中=${stage.hits}');
    expect(stage.hits, 1);
    expect(identical(a, b), isTrue);
  });

  test('B19 key 归一化：query 顺序不同算同一条', () async {
    final _CountingStage stage = _CountingStage();
    final Resolver r = Resolver(stages: <ResolveStage>[stage]);

    await r.resolve('https://x.com/p?b=2&a=1');
    await r.resolve('https://x.com/p?a=1&b=2');
    // ignore: avoid_print
    print('[cache] 归一化后上游命中=${stage.hits} cacheSize=${r.cacheSize}');
    expect(stage.hits, 1);
  });

  test('B19-d expiresAt 改成过去 → 重新请求', () async {
    final _CountingStage stage = _CountingStage();
    final Resolver r = Resolver(stages: <ResolveStage>[stage]);

    await r.resolve('https://x.com/p?a=1');
    final int n = r.debugExpireAll();
    final ResolvedUrl again = await r.resolve('https://x.com/p?a=1');
    // ignore: avoid_print
    print('[cache] 过期条数=$n 重新请求后上游命中=${stage.hits} url=${again.url}');
    expect(n, 1);
    expect(stage.hits, 2);
  });

  test('cacheKey 把 scheme/host 小写、丢 fragment、排序 query', () {
    final String k = Resolver.cacheKey('HTTPS://X.COM/P?b=2&a=1#frag');
    // ignore: avoid_print
    print('[cache] key=$k');
    expect(k, 'https://x.com/P?a=1&b=2');
  });

  test('LRU 上限 200 条，超了淘汰最早的', () async {
    final _CountingStage stage = _CountingStage();
    final Resolver r = Resolver(stages: <ResolveStage>[stage]);
    for (int i = 0; i < 205; i++) {
      await r.resolve('https://x.com/v/$i');
    }
    // ignore: avoid_print
    print('[cache] 写入 205 条后 cacheSize=${r.cacheSize}');
    expect(r.cacheSize, Resolver.cacheLimit);
  });
}
