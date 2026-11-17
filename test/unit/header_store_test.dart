import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yiqikan/data/local/header_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('任意键值对：加、改、删都能立刻落盘并读回', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final HeaderStore store = HeaderStore();

    // 加三条（不是只有 Referer）
    await store.put('a.com', <String, String>{
      'Referer': 'https://a.com/p',
      'User-Agent': 'YiqikanTest/1.0',
      'X-Custom-Token': 'abc',
    });
    Map<String, String> h = await store.headersFor('https://a.com/v.m3u8');
    expect(h.length, 3);
    expect(h['X-Custom-Token'], 'abc');

    // 改一条 + 删一条
    await store.put('a.com', <String, String>{
      'Referer': 'https://a.com/p2',
      'X-Custom-Token': 'def',
    });
    h = await store.headersFor('https://a.com/v.m3u8');
    expect(h.length, 2);
    expect(h['Referer'], 'https://a.com/p2');
    expect(h.containsKey('User-Agent'), isFalse);

    // 子域也命中
    expect(
      (await store.headersFor('https://cdn.a.com/x.mp4'))['X-Custom-Token'],
      'def',
    );

    // 别的站点不串
    expect(await store.headersFor('https://b.com/x.mp4'), isEmpty);

    // 删除整站规则
    await store.remove('a.com');
    expect(await store.headersFor('https://a.com/x.mp4'), isEmpty);
  });

  test('base headers 会被站点规则覆盖', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final HeaderStore store = HeaderStore();
    await store.put('a.com', <String, String>{'Referer': 'https://a.com/p'});
    final Map<String, String> h = await store.headersFor(
      'https://a.com/x.m3u8',
      base: <String, String>{'Referer': 'https://old/', 'Accept': '*/*'},
    );
    expect(h['Referer'], 'https://a.com/p');
    expect(h['Accept'], '*/*');
  });
}
