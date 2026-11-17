import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/local/prefs.dart';

/// 需要引导的五种权限（G10）。
enum PermKind {
  notification,
  mediaVideo,
  camera,
  microphone,

  /// 「安装未知应用」不是运行时权限：只能查 `canRequestPackageInstalls()`，
  /// 引导用户去系统设置页打开，所以它单独走 MethodChannel。
  installUnknown,
}

/// 四种状态（UI 上就是「绿勾 / 申请 / 再试一次 / 去系统设置」）。
enum PermState { granted, denied, permanentlyDenied, notRequested }

extension PermStateX on PermState {
  String get label => switch (this) {
        PermState.granted => '已授权',
        PermState.denied => '被拒绝',
        PermState.permanentlyDenied => '已永久拒绝',
        PermState.notRequested => '未申请',
      };

  /// 右侧按钮文案；null = 不需要按钮（已授权）。
  String? get actionLabel => switch (this) {
        PermState.granted => null,
        PermState.denied => '再试一次',
        PermState.permanentlyDenied => '去系统设置',
        PermState.notRequested => '申请',
      };

  bool get canRequest => this == PermState.denied || this == PermState.notRequested;
}

/// 把 permission_handler 的 `PermissionStatus` 归一成四档。
///
/// 抽出来是为了可单测：真机上「永久拒绝」要两次拒绝才出现，跑一次很难造。
PermState normalizeStatus({required bool granted, required bool permanentlyDenied,
        required bool denied, required bool restricted}) =>
    granted
        ? PermState.granted
        : permanentlyDenied
            ? PermState.permanentlyDenied
            : (denied || restricted)
                ? PermState.denied
                : PermState.notRequested;

/// 权限引导的入口（页面只调这两个方法）。
class PermissionGuide {
  const PermissionGuide._();

  static const MethodChannel _install = MethodChannel('yiqikan/install');

  static String titleOf(PermKind k) => switch (k) {
        PermKind.notification => '通知',
        PermKind.mediaVideo => '照片和视频',
        PermKind.camera => '相机',
        PermKind.microphone => '麦克风',
        PermKind.installUnknown => '安装未知应用',
      };

  static String whyOf(PermKind k) => switch (k) {
        PermKind.notification => '下载完成、房间邀请、后台播放控制',
        PermKind.mediaVideo => '媒体库扫描本机视频',
        PermKind.camera => '扫码加房',
        PermKind.microphone => '语音房间说话',
        PermKind.installUnknown => '应用内安装更新包（只允许装自己下载的那一个）',
      };

  static Permission? _permissionOf(PermKind k) => switch (k) {
        PermKind.notification => Permission.notification,
        PermKind.mediaVideo => Permission.videos,
        PermKind.camera => Permission.camera,
        PermKind.microphone => Permission.microphone,
        PermKind.installUnknown => null,
      };

  static Future<PermState> status(PermKind k) async {
    if (k == PermKind.installUnknown) {
      try {
        final bool ok = await _install.invokeMethod<bool>('canInstall') ?? false;
        return ok ? PermState.granted : PermState.notRequested;
      } on Object catch (e) {
        debugPrint('[YQK-PERM] canInstall fail: $e');
        return PermState.notRequested;
      }
    }
    final Permission? p = _permissionOf(k);
    if (p == null) return PermState.notRequested;
    final PermissionStatus s = await p.status;
    return normalizeStatus(
      granted: s.isGranted || s.isLimited,
      permanentlyDenied: s.isPermanentlyDenied,
      denied: s.isDenied,
      restricted: s.isRestricted,
    );
  }

  /// 申请。`installUnknown` 走系统设置页（不弹框），返回前先打开设置。
  static Future<PermState> request(PermKind k) async {
    if (k == PermKind.installUnknown) {
      try {
        await _install.invokeMethod<bool>('openSettings');
      } on Object catch (e) {
        debugPrint('[YQK-PERM] openSettings fail: $e');
        await openAppSettings();
      }
      debugPrint('[YQK-PERM] request kind=${k.name} -> openSettings');
      return PermState.notRequested;
    }
    final Permission? p = _permissionOf(k);
    if (p == null) return PermState.notRequested;
    final PermissionStatus s = await p.request();
    PermState st = normalizeStatus(
      granted: s.isGranted || s.isLimited,
      permanentlyDenied: s.isPermanentlyDenied,
      denied: s.isDenied,
      restricted: s.isRestricted,
    );
    // Android 上 status/request 永远不会回 permanentlyDenied（插件源码注释：
    // 「a status check can never resolve to 'permanently denied'」），
    // 所以自己数次数：连续两次申请仍被拒 → 当作永久拒绝，UI 才会给「去系统设置」。
    st = await _bumpIfDenied(k, st);
    debugPrint('[YQK-PERM] request kind=${k.name} raw=$s -> ${st.name}');
    return st;
  }

  /// 申请被拒时给该权限的「已尝试次数」+1；第二次仍被拒就降级成永久拒绝。
  static Future<PermState> _bumpIfDenied(PermKind k, PermState st) async {
    if (st != PermState.denied) return st;
    try {
      final Prefs prefs = await Prefs.open();
      final String key = 'perm_try_${k.name}';
      final int n = (prefs.getInt(key) ?? 0) + 1;
      await prefs.setInt(key, n);
      if (n >= 2) {
        debugPrint('[YQK-PERM] kind=${k.name} denied x$n -> permanentlyDenied');
        return PermState.permanentlyDenied;
      }
    } on Object catch (e) {
      debugPrint('[YQK-PERM] try count fail: $e');
    }
    return st;
  }

  /// 永久拒绝 / 安装未知应用 → 打开系统页。
  static Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } on Object catch (e) {
      debugPrint('[YQK-PERM] openAppSettings fail: $e');
      return false;
    }
  }
}
