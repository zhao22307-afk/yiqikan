import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// G13 省电与后台策略：电池优化白名单的读写。
///
/// 只包两个原生调用，UI 在 `features/settings/power_page.dart`。
class PowerGuide {
  const PowerGuide._();

  static const MethodChannel _ch = MethodChannel('yiqikan/power');

  /// 当前是否在「电池优化白名单」（= 系统不限制后台）。
  static Future<bool?> isIgnoringBattery() async {
    try {
      return await _ch.invokeMethod<bool>('isIgnoringBattery');
    } on Object catch (e) {
      debugPrint('[YQK-POWER] isIgnoringBattery fail: $e');
      return null;
    }
  }

  /// 拉起系统页（ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS + package: URI）。
  ///
  /// 这个 intent 只有用户主动点击时才发，不静默申请；用途写在页面上。
  static Future<bool> requestIgnoreBattery() async {
    try {
      final bool ok = await _ch.invokeMethod<bool>('requestIgnoreBattery') ?? false;
      debugPrint('[YQK-POWER] requestIgnoreBattery ok=$ok');
      return ok;
    } on Object catch (e) {
      debugPrint('[YQK-POWER] requestIgnoreBattery fail: $e');
      return false;
    }
  }

  /// 后台行为说明（页面上纯文字，写死在这里方便单测/审计）。
  static const List<(String, String)> notes = <(String, String)>[
    ('屏幕共享', '有前台服务（通知「一起看 · 正在共享屏幕」），锁屏后继续共享。'),
    ('语音通话', 'WebRTC 自带心跳；但系统进入 Doze 深度睡眠时可能降级甚至断开。'),
    ('房间服务', 'App 退到后台超过 10 分钟，系统可能冻结本地服务，房间会掉。'),
    ('下载', '队列在内存里，App 被系统杀掉就停；本版没有前台服务保活，重开 App 会从断点续。'),
  ];
}
