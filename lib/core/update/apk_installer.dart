import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// G8 安装落地：把校验过的 APK 交给系统安装器。
///
/// **复用** MainActivity 里已有的 `yiqikan/install` 通道（批 E10 之前就在，
/// 原始实现是 FileProvider + ACTION_VIEW + FLAG_GRANT_READ_URI_PERMISSION）：
/// - `canInstall` → `packageManager.canRequestPackageInstalls()`
/// - `openSettings` → `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES`
/// - `install(path)` → `installApk(path)`
///
/// 因此本轮 MainActivity 只加了一条 `[YQK-UPD]` 日志，没有新增通道。
class ApkInstaller {
  ApkInstaller._();

  static const MethodChannel _ch = MethodChannel('yiqikan/install');

  /// 是否已获得「安装未知应用」权限
  static Future<bool> canInstall() async {
    try {
      final bool? ok = await _ch.invokeMethod<bool>('canInstall');
      debugPrint('[YQK-UPD] canInstall=$ok');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('[YQK-UPD] canInstall fail ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('[YQK-UPD] canInstall fail: channel 缺失');
      return false;
    }
  }

  /// 跳到系统的「安装未知应用」设置页（让用户自己开，不静默申请）
  static Future<void> openUnknownSources() async {
    try {
      await _ch.invokeMethod<void>('openSettings');
      debugPrint('[YQK-UPD] openUnknownSources ok');
    } catch (e) {
      debugPrint('[YQK-UPD] openUnknownSources fail $e');
    }
  }

  /// 拉起安装器；返回 'ok' / 错误文案
  static Future<String> install(File apk) async {
    try {
      final bool? r = await _ch.invokeMethod<bool>(
        'install',
        <String, Object?>{'path': apk.path, 'size': await apk.length()},
      );
      debugPrint('[YQK-UPD] install result=$r path=${apk.path}');
      return r == true ? 'ok' : 'installer 拒绝（检查 file_paths 是否有 update/）';
    } on PlatformException catch (e) {
      debugPrint('[YQK-UPD] install fail ${e.code} ${e.message}');
      return '${e.code}: ${e.message}';
    } on MissingPluginException {
      debugPrint('[YQK-UPD] install fail: channel 缺失');
      return 'channel 缺失';
    }
  }
}
