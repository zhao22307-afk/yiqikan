import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/error/error_log.dart';
import 'core/error/error_page.dart';
import 'core/logger.dart';
import 'core/notify/notifier.dart';
import 'platform/tvbox/qjs_probe.dart';
import 'core/theme/theme_controller.dart';
import 'data/local/prefs.dart';
import 'data/local/secure_store.dart';

/// 进程启动时刻（`[YQK-BOOT]` 用，算冷启到首帧的毫秒数）。
final Stopwatch _bootWatch = Stopwatch()..start();

/// 入口只做三件事：绑引擎 → 起 media_kit → 起应用。
///
/// 内置服务由 Android 侧 `top.yiqikan.app.server.LocalApp` 在进程启动时拉起，
/// 这里不 await 任何网络操作（MUST NOT 之一）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[YQK-BOOT] main start t=0ms');
  _installErrorHandlers();
  // 15 §A1：media_kit 必须先初始化，否则 Player() 构造会抛
  MediaKit.ensureInitialized();
  // 15 §A11：日志收集（环形缓冲 500 行），高级面板里透出用
  AppLog.install();
  // 03 §5：启动时探一次凭据存储，降级了要能一眼看出来
  if (kDebugMode) unawaited(_probeSecureStore());
  // P-1：Java 源集探针（只在 debug 打日志）
  if (kDebugMode) unawaited(_probeJava());
  // G2 / G12：主题与字号在首帧前就位，避免启动时闪一下浅色再变深色。
  await _applyAppearancePrefs();
  debugPrint('[YQK-BOOT] prefs applied t=${_bootWatch.elapsedMilliseconds}ms');
  // G9：通知通道（三个 channel）+ 点击回调。失败只打日志，不挡启动。
  unawaited(AppNotifier.instance.init());
  _logFirstFrame();
  runApp(ProviderScope(
    child: YiqikanApp(initialLocation: _initialLocation()),
  ));
  debugPrint('[YQK-BOOT] runApp returned t=${_bootWatch.elapsedMilliseconds}ms');
}

/// 首帧回调（HomePage 也会打一条；这里兜底记一笔进程内耗时）。
void _logFirstFrame() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[YQK-BOOT] first frame t=${_bootWatch.elapsedMilliseconds}ms');
  });
}

/// G7 崩溃兜底：build 期 / 未捕获异步异常都要留痕，且不能红屏。
void _installErrorHandlers() {
  // build 期异常：把红屏换成 ErrorPage（细节仍进日志）。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // G7：兜底页要出现时先把日志写下去 —— 进程接下来可能被系统杀掉，
    // 500ms 的节流窗口等不起，这里 fire-and-forget 强制刷一次。
    unawaited(ErrorLog.flushNow());
    return ErrorPage(
      detail: details.exceptionAsString(),
    );
  };

  // 框架内异常（build/layout/paint 同步抛出）。
  FlutterError.onError = (FlutterErrorDetails details) {
    // 框架的「非异常诊断」（ListTile 颜色提示之类）也走这条通道，但没有栈；
    // 只记有栈的，免得把 50 条的环形缓存冲干净、把真正的崩溃挤出去。
    if (details.stack != null) {
      ErrorLog.add('build', details.exception, details.stack);
    }
    debugPrint('[YQK-ERR] flutter ${details.exceptionAsString()}');
    final String? lib = details.library;
    if (lib != null) debugPrint('[YQK-ERR] at $lib');
    FlutterError.presentError(details);
  };

  // 平台层未捕获异常（Future 里 throw 且没人 await）。
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    ErrorLog.add('async', error, stack);
    debugPrint('[YQK-ERR] async $error');
    debugPrint('[YQK-ERR] async stack=${stack.toString().split('\n').take(3).join(' | ')}');
    return true;
  };
}

/// 读 prefs 里的 theme_mode / font_scale / locale 写进 ThemeController。
Future<void> _applyAppearancePrefs() async {
  try {
    final Prefs p = await Prefs.open();
    ThemeController.pref =
        ThemeController.prefFromName(p.getString(PrefKeys.themeMode));
    ThemeController.fontScale = p.getDouble(PrefKeys.fontScale) ?? 1.0;
    ThemeController.localePref =
        ThemeController.localeFromName(p.getString(PrefKeys.locale));
    debugPrint('[YQK-THEME] boot pref=${ThemeController.prefName(ThemeController.pref)} '
        'font=${ThemeController.fontScale}');
    debugPrint(
        '[YQK-L10N] boot locale=${ThemeController.localeName(ThemeController.localePref)} '
        'effective=${ThemeController.effectiveLocale?.toLanguageTag() ?? 'system'}');
  } on Object catch (e) {
    debugPrint('[YQK-THEME] boot read fail: $e');
  }
}

/// 03 §5 的降级自查：写一个探针 key 再读回来，把后端与降级状态打进日志。
/// 只记状态，不记任何业务凭据内容。
Future<void> _probeSecureStore() async {
  final SecureStore store = SecureStore();
  const String probeKey = 'diag_probe';
  try {
    await store.put(probeKey, 'ping');
    final String? back = await store.get(probeKey);
    debugPrint('[YQK-SECURE] backend=KeyStore(AES-GCM + RSA-OAEP) '
        'degraded=${store.isDegraded}');
    debugPrint('[YQK-SECURE] roundtrip key=$probeKey write=ping read=$back');
    await store.delete(probeKey);
  } on Object catch (e) {
    debugPrint('[YQK-SECURE] 探针失败：$e degraded=${store.isDegraded}');
  }
}

/// 探针：确认 Java 源集与本机 MethodChannel 通（P-1 / P0a / P0b / P0c）。
/// 只打日志，失败也只打日志，不影响启动。
Future<void> _probeJava() async {
  const MethodChannel ch = MethodChannel('yiqikan/probe');
  // 只留 ping：P0e 之前那几个探针（probeJarScan / tvboxBatch）每次启动都会
  // 白跑 113 源批量扫描（每源 10s 超时），把验收日志和网络都搅了。
  for (final String m in <String>['ping']) {
    try {
      final Object? r = await ch.invokeMethod<Object?>(m);
      debugPrint('[YQK-PROBE] ${r ?? 'null'}');
      if (r is String && r.startsWith('ERR')) {
        // 失败只要日志，验收看 P0x-V4 的原文
      }
    } on Object catch (e) {
      debugPrint('[YQK-PROBE] ERR $m -> $e');
      break;
    }
  }
  // P3：QuickJS 自检（工作线程在 Java 侧起，这里只等结果）
  try {
    final String? q = await QjsProbe.ping();
    if (q != null && q.isNotEmpty) debugPrint('[YQK-QJS] $q');
  } on Object catch (e) {
    debugPrint('[YQK-QJS] probe failed -> $e');
  }
}

/// 把 Android 深链 `yiqikan://play?url=...` 翻成路由路径 `/play?url=...`。
///
/// 只认 play 这一条：其余深链（房间等）由各自里程碑接管，落回首页。
String? _initialLocation() {
  final String raw =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  if (raw.isEmpty || raw == '/') return null;
  final Uri? uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'yiqikan') {
    // 普通路径（含 Flutter 自己的初始路由）原样交给路由表
    return raw.startsWith('/') ? raw : null;
  }
  final String host = uri.host;
  final String path = uri.path.isEmpty ? '' : uri.path;
  final String routePath = '/$host$path';
  if (routePath.startsWith('/play')) {
    final String query = uri.hasQuery ? '?${uri.query}' : '';
    return '$routePath$query';
  }
  return null;
}
