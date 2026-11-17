import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'playback_kernel.dart';

/// Anime4K 画质分级（04 §12.1–§12.2）。
///
/// **Android 上一律 `off`**：见 04 §12.6.1 —— Android 上挂任何 `glsl-shaders`
/// 都静默黑屏（视频区全黑、有声音、时间在走），连 10 行反色 shader 都会黑
/// （2026-11-05 本机实测，MAD 87 / 亮度 0.10）。链定义与挂/卸接口保留，
/// 等自编带 libplacebo 的 libmpv 或换 fvp 内核再启用。
///
/// 画质增强改走 mpv 内置缩放器，见 `scaler_profile.dart`。
enum Anime4kLevel { off, light, medium, high }

/// Anime4K shader 链。文件名顺序不能乱：Clamp 永远第一（防高光溢出），
/// AutoDownscalePre 在 Restore 前（先缩放再修复），Restore 在 Upscale 前。
class Anime4k {
  const Anime4k._();

  /// 默认档位：写死 off（Android 不可用，04 §12.7 表 1/2/4/5/6 全部阻塞）
  static const Anime4kLevel defaultLevel = Anime4kLevel.off;

  /// assets 下的目录（pubspec 里已声明）
  static const String assetDir = 'assets/shaders';

  /// 三档链，off 就是空链
  static const Map<Anime4kLevel, List<String>> chains =
      <Anime4kLevel, List<String>>{
    Anime4kLevel.off: <String>[],
    Anime4kLevel.light: <String>[
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_S.glsl',
      'Anime4K_Upscale_CNN_x2_S.glsl',
    ],
    Anime4kLevel.medium: <String>[
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    Anime4kLevel.high: <String>[
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Restore_CNN_VL.glsl',
      'Anime4K_Upscale_CNN_x2_VL.glsl',
    ],
  };

  /// 把 assets 里的 glsl 落到磁盘并返回**绝对路径**。
  ///
  /// 为什么要落盘：`glsl-shaders` 吃的是文件系统路径，APK 里的 assets
  /// 没有真实路径可给。
  static Future<List<String>> materialize(Anime4kLevel level) async {
    final List<String> files = chains[level] ?? <String>[];
    if (files.isEmpty) return <String>[];
    final Directory support = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(support.path, 'shaders'));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final List<String> out = <String>[];
    for (final String name in files) {
      final File target = File(p.join(dir.path, name));
      // 已落过盘就复用（shader 是静态资源，内容不会变）
      if (!target.existsSync() || target.lengthSync() == 0) {
        final ByteData data = await rootBundle.load('$assetDir/$name');
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      out.add(target.path);
    }
    return out;
  }

  /// 挂/卸 shader 链。
  ///
  /// **Android 直接 return**：04 §12.6.1 —— Android 上挂任何 `glsl-shaders`
  /// 静默黑屏，所以在这里就挡住，别让调用方把播放器搞黑。
  /// iOS/桌面端照常挂（那边的 vo 是真 gpu 渲染管线）。
  static Future<void> setAnimeLevel(
    PlaybackKernel kernel,
    Anime4kLevel level,
  ) async {
    if (Platform.isAndroid) {
      // 见 04 §12.6.1：Android 上挂任何 glsl-shaders 静默黑屏（实测连反色 shader 都黑）
      if (kDebugMode && level != Anime4kLevel.off) {
        debugPrint('[YQK-A4K] Android 忽略 ${level.name}：glsl-shaders 会黑屏');
      }
      return;
    }
    final List<String> paths = await materialize(level);
    await kernel.setShaderChain(paths);
  }

  /// 拼成 mpv 的 `glsl-shaders` 值：分隔符是**冒号**（mpv 的 path list 用 ':'，
  /// 逗号会被当成一个文件名）。
  static String chainValue(List<String> absolutePaths) =>
      absolutePaths.isEmpty ? '' : absolutePaths.join(':');
}
