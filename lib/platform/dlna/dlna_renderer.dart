import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// M10 C 组：本机当 MediaRenderer 的 Dart 侧桥。
///
/// Java 侧（`DlnaRenderer.java`）负责 SSDP 响应 + SOAP 解析，把收到的命令
/// 压进队列；播放器在 Dart 里，所以由这里定时轮询 `/dlna/pending` 取命令，
/// 再作用到当前的 PlayerController。
///
/// 只在「房间内且是房主」时开：两个播放器抢同一个片子会互相打架（15 号 H9 的坑）。
class DlnaRendererBridge {
  DlnaRendererBridge({
    required this.base,
    required this.onCommand,
    this.interval = const Duration(milliseconds: 700),
    this.onLog,
  });

  /// 本机服务基址，例如 `http://127.0.0.1:8080`
  final String base;

  /// 收到一条命令：`{'cmd': 'SetAVTransportURI'|'Play'|'Pause'|'Stop'|'Seek', ...}`
  final void Function(Map<String, dynamic> cmd) onCommand;

  final Duration interval;
  final void Function(String)? onLog;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 2),
  ));

  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;

  void _log(String s) => (onLog ?? (String _) {})(s);

  /// 打开接收端并开始轮询。
  Future<void> start(String name) async {
    if (_timer != null) return;
    _stopped = false;
    try {
      final Response<dynamic> r =
          await _dio.get('$base/local/dlna/renderer', queryParameters: <String, dynamic>{
        'on': '1',
        'name': name,
      });
      _log('[YQK-DLNA] bridge start running=${r.data is Map ? (r.data as Map)['running'] : '?'}');
    } catch (e) {
      _log('[YQK-DLNA] bridge start fail $e');
      return;
    }
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    try {
      await _dio.get('$base/local/dlna/renderer', queryParameters: <String, dynamic>{'on': '0'});
      _log('[YQK-DLNA] bridge stop');
    } catch (e) {
      _log('[YQK-DLNA] bridge stop fail $e');
    }
  }

  Future<void> _tick() async {
    if (_busy || _stopped) return;
    _busy = true;
    try {
      final Response<dynamic> r = await _dio.get('$base/dlna/pending');
      final dynamic data = r.data;
      if (data is Map) {
        final dynamic cmd = data['cmd'];
        if (cmd is Map) {
          final Map<String, dynamic> m = cmd.map<String, dynamic>(
              (dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v));
          _log('[YQK-DLNA] take cmd=${m['cmd']}');
          onCommand(m);
        }
      }
    } catch (_) {
      // 轮询失败不刷屏：服务没起来时每 700ms 一条会淹掉日志
    } finally {
      _busy = false;
    }
  }

  /// 解析 hms 秒数（Java 侧已经转好了，这里只是备用）
  static double asSeconds(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final double? d = double.tryParse(v);
      if (d != null) return d;
    }
    return 0;
  }

  /// 供 UI 显示：把 JSON 里的中文转成安全字符串（防 null）
  static String s(Object? v) => v == null ? '' : '$v';

  /// base 上拼一个查询串（path 里的中文/空格要编码）
  static String query(String base, String path, Map<String, String> extra) {
    final StringBuffer sb = StringBuffer(base);
    sb.write(path.contains('?') ? '&' : '?');
    final List<String> parts = <String>[];
    extra.forEach((String k, String v) {
      parts.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(v)}');
    });
    sb.write(parts.join('&'));
    return sb.toString();
  }

  static String jsonOf(Object? v) => jsonEncode(v ?? const <String, dynamic>{});
}
