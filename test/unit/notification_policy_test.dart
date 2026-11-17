import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/notify/notifier.dart';

/// B-V5 的「拒绝后不再弹」目前在真机上造不出来（vivo API36 对这个 App 的
/// POST_NOTIFICATIONS 请求直接放行，系统不弹框），所以把守卫抽成纯函数单测。
void main() {
  test('系统已开启时不需要请求', () {
    expect(AppNotifier.shouldRequest(enabled: true, asked: false), isFalse);
    expect(AppNotifier.shouldRequest(enabled: true, asked: true), isFalse);
  });

  test('系统没开且没问过 → 请求一次', () {
    expect(AppNotifier.shouldRequest(enabled: false, asked: false), isTrue);
  });

  test('系统没开但已经问过 → 不再弹', () {
    expect(AppNotifier.shouldRequest(enabled: false, asked: true), isFalse);
  });
}
