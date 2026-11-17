import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'parse.dart';

/// 深链桥：Java 侧 `MainActivity` 通过 `top.yiqikan.app/deeplink` 把链接交过来，
/// 冷启动那条用 `getInitialLink` 主动取。
///
/// 为什么不让 Java 直接 `pushRoute('/join?code=…')`：路由串表达不了 pwd，
/// 也表达不了"这条是从链接来的"（文案不一样），所以统一在 Dart 里解析。
class DeepLinkBridge {
  DeepLinkBridge._();

  static const MethodChannel _channel = MethodChannel('top.yiqikan.app/deeplink');

  static bool _attached = false;

  /// 注册回调并取一次冷启动链接。重复调用无副作用（热重启后仍是同一实例）。
  static Future<void> attach(void Function(RoomLink link) onLink) async {
    if (_attached) return;
    _attached = true;

    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'onDeepLink') return null;
      final Object? arg = call.arguments;
      if (arg is! String) return null;
      final RoomLink? link = parseRoomLink(arg);
      debugPrint('[YQK-LINK] onDeepLink url=$arg -> ${link ?? '(dropped: 解析不出房间码)'}');
      if (link != null) onLink(link);
      return null;
    });

    try {
      final String? initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.isNotEmpty) {
        final RoomLink? link = parseRoomLink(initial);
        debugPrint('[YQK-LINK] cold url=$initial -> ${link ?? '(dropped: 解析不出房间码)'}');
        if (link != null) onLink(link);
      } else {
        debugPrint('[YQK-LINK] cold url=(none)');
      }
    } on PlatformException catch (e) {
      debugPrint('[YQK-LINK] getInitialLink 失败：$e');
    } on MissingPluginException {
      // 桌面/测试环境没有这个通道，静默跳过
      debugPrint('[YQK-LINK] 无 deeplink 通道（非 Android），跳过');
    }
  }

  @visibleForTesting
  static Future<void> handleRaw(String? raw, void Function(RoomLink link) onLink) async {
    final RoomLink? link = parseRoomLink(raw);
    if (link != null) onLink(link);
  }
}
