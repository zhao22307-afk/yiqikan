import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/local/prefs.dart';
import 'fvp_kernel.dart';
import 'mpv_kernel.dart';
import 'playback_kernel.dart';

/// 播放内核种类（15 §A4 / 12 §4.4）。
///
/// `auto` = 默认 mpv，fvp 只在「用户手动选 fvp」或「mpv 打不开」时上场；
/// 具体兜底在 [PlayerController] 里做，这里只负责造对象与能力判定。
enum KernelKind {
  /// 按平台自动选：Android 有 fvp，桌面只有 mpv
  auto,
  mpv,
  fvp;

  /// 存 pref 的字符串值
  String get prefValue => name;

  /// 给人看的名字
  String get label {
    switch (this) {
      case KernelKind.auto:
        return '自动';
      case KernelKind.mpv:
        return 'mpv';
      case KernelKind.fvp:
        return 'fvp';
    }
  }
}

/// 内核工厂：只管「按种类造一个」，不负责兜底（那是控制器的活）。
class KernelFactory {
  const KernelFactory._();

  /// fvp 只在移动端接（桌面交给 mpv，fvp 的桌面后端不在本次目标里）
  static bool get fvpAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 把用户选择解析成真正要用的内核
  static KernelKind resolve(KernelKind wanted) {
    switch (wanted) {
      case KernelKind.auto:
        return KernelKind.mpv;
      case KernelKind.fvp:
        return fvpAvailable ? KernelKind.fvp : KernelKind.mpv;
      case KernelKind.mpv:
        return KernelKind.mpv;
    }
  }

  /// 造内核。fvp 造不出来会抛（缺 so / MDK 初始化失败），调用方接住降级。
  static PlaybackKernel create(KernelKind kind) {
    switch (kind) {
      case KernelKind.fvp:
        if (!fvpAvailable) {
          throw UnsupportedError('这个平台没有 fvp 内核');
        }
        return FvpKernel();
      case KernelKind.mpv:
      case KernelKind.auto:
        return MpvKernel();
    }
  }

  /// 读 pref 里的选择（缺省 auto）
  static KernelKind fromPref(Prefs? prefs) {
    final String? raw = prefs?.getString(PrefKeys.kernelKind);
    switch (raw) {
      case 'mpv':
        return KernelKind.mpv;
      case 'fvp':
        return KernelKind.fvp;
      default:
        return KernelKind.auto;
    }
  }
}
