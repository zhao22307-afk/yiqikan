import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// D20 第一步：屏幕采集。
///
/// 只负责「房主本机拿到一条屏幕视频轨」，**不推流、不进房间、不发任何 WS 帧**。
/// 这一步的目的是确认 targetSdk=36 下 MediaProjection 授权链能否走通，
/// 以及拿到的 track 真实分辨率/帧率是多少（系统会按屏幕尺寸给，不是我们传的值）。
///
/// 用法：
/// ```dart
/// final ScreenShare s = ScreenShare(onLog: debugPrint);
/// if (await s.start()) { … }
/// await s.stop();
/// ```
class ScreenShare {
  ScreenShare({this.onLog});

  /// 日志出口，默认不打。页面上传 `debugPrint`，方便统一用 `[YQK-SCREEN]` 过滤。
  final void Function(String)? onLog;

  MediaStream? _stream;

  /// 第44轮实验：先拉一个 `foregroundServiceType=mediaProjection` 的前台服务，
  /// 再调 getDisplayMedia —— Android 的 getMediaProjection 就检查进程里有没有它。
  static const MethodChannel _ch = MethodChannel('yiqikan/screen');

  /// 是否正在共享（已拿到 stream）
  bool get active => _stream != null;

  /// 当前 stream 里的轨道数（视频 1 条；audio 关掉所以通常是 1）
  int get trackCount => _stream?.getTracks().length ?? 0;

  /// 第47轮：把这条屏幕视频轨交给 ScreenEngine 推到客人。没有流时返回 null。
  MediaStreamTrack? get screenTrack {
    final List<MediaStreamTrack> v = _stream?.getVideoTracks() ?? <MediaStreamTrack>[];
    return v.isEmpty ? null : v.first;
  }

  /// D20 音频（第49轮）：Android 侧实测恒为空；留给 ScreenEngine 判断。
  List<MediaStreamTrack> get audioTracks =>
      _stream?.getAudioTracks() ?? <MediaStreamTrack>[];

  /// 请求屏幕采集。
  ///
  /// [width]/[height]/[fps] 只是**期望值**：Android 的 MediaProjection 会按物理屏
  /// 分辨率出图，实际值要从 `track.getSettings()` 读（V2 验收就是看这个真值）。
  ///
  /// 任何异常都在这里吃掉并打日志，返回 false —— 拒绝授权也不许冒到 UI。
  Future<bool> start({int width = 720, int height = 1280, int fps = 15}) async {
    // 必须赶在 getDisplayMedia 之前把前台服务立起来，否则 getMediaProjection 直接
    // 抛 SecurityException（第43轮真机栈就在 startCapture:131）。
    try {
      await _ch.invokeMethod<bool>('start');
      _log('[YQK-SCREEN] svc start ok');
    } catch (e) {
      _log('[YQK-SCREEN] svc start fail $e');
    }
    // 给 onStartCommand 跑完 startForeground 的时间；没有这 400ms 竞态会让结论不可信。
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // 第46轮：Android 14+ 首次（从未授权过 MediaProjection）startForeground 会失败，
    // 走过一次授权流程后就永久 ok（第45轮 vivo/API36 实测）。所以这里问一下 Java 侧
    // 到底成没成，没成就先"热身"一次授权把 appop 打上，再起服务。
    final bool fg = await _fgOk();
    _log('[YQK-SCREEN] cold fg=$fg');
    if (!fg) {
      _log('[YQK-SCREEN] warmup begin');
      // 这一段**预期会被用户取消或抛异常**，全部吞掉，不许冒到 UI。
      try {
        final MediaStream warm =
            await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
          'video': <String, dynamic>{
            'width': width,
            'height': height,
            'frameRate': fps,
          },
          'audio': false,
        });
        final int wn = warm.getTracks().length;
        for (final MediaStreamTrack t in warm.getTracks()) {
          try {
            await t.stop();
          } catch (_) {
            // 热身流停不掉也不影响后面
          }
        }
        _log('[YQK-SCREEN] warmup got tracks=$wn');
      } catch (e) {
        _log('[YQK-SCREEN] warmup swallowed $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      try {
        await _ch.invokeMethod<bool>('start');
        _log('[YQK-SCREEN] svc start ok');
      } catch (e) {
        _log('[YQK-SCREEN] svc start fail $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final bool fg2 = await _fgOk();
      _log('[YQK-SCREEN] after warmup fg=$fg2');
      if (!fg2) {
        _log('[YQK-SCREEN] give up fg still false');
        try {
          await _ch.invokeMethod<bool>('stop');
          _log('[YQK-SCREEN] svc stop');
        } catch (_) {
          _log('[YQK-SCREEN] svc stop fail');
        }
        return false;
      }
    }

    try {
      final MediaStream s =
          await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
        'video': <String, dynamic>{
          'width': width,
          'height': height,
          'frameRate': fps,
        },
        'audio': true,
      });
      _stream = s;
      // D20 音频探测（第49轮）：Android 侧 getDisplayMedia 到底带不带音轨。
      // ac == 0 也继续走，视频照旧；不许因为没音轨就 return false。
      final List<MediaStreamTrack> audios = s.getAudioTracks();
      final int ac = audios.length;
      _log('[YQK-SCREEN] audio tracks=$ac');
      for (final MediaStreamTrack a in audios) {
        _log('[YQK-SCREEN] audio track kind=${a.kind} id=${a.id} '
            'enabled=${a.enabled} muted=${a.muted}');
      }
      for (final MediaStreamTrack t in s.getVideoTracks()) {
        _log('[YQK-SCREEN] track id=${t.id} label=${t.label} '
            'enabled=${t.enabled} muted=${t.muted}');
        try {
          // flutter_webrtc 1.6.3 的 getSettings() 是同步返回 Map，不是 Future
          final Map<String, dynamic> st = t.getSettings();
          _log('[YQK-SCREEN] settings width=${st['width']} '
              'height=${st['height']} frameRate=${st['frameRate']}');
        } catch (e) {
          // 有的机型不给 settings，这不算失败
          _log('[YQK-SCREEN] settings unavailable $e');
        }
      }
      return true;
    } catch (e) {
      _log('[YQK-SCREEN] start fail $e');
      // 起不来就别把前台服务留在后台跑（V6：拒绝授权也必须看到 fg stop）
      try {
        await _ch.invokeMethod<bool>('stop');
        _log('[YQK-SCREEN] svc stop');
      } catch (_) {
        _log('[YQK-SCREEN] svc stop fail');
      }
      return false;
    }
  }

  /// 停止采集：逐条 track.stop()，清空 stream。
  Future<void> stop() async {
    final MediaStream? s = _stream;
    _stream = null;
    if (s == null) {
      _log('[YQK-SCREEN] stop tracks=0');
      return;
    }
    final List<MediaStreamTrack> tracks = s.getTracks();
    final int n = tracks.length;
    for (final MediaStreamTrack t in tracks) {
      try {
        await t.stop();
      } catch (e) {
        _log('[YQK-SCREEN] stop track fail ${t.id} $e');
      }
    }
    _log('[YQK-SCREEN] stop tracks=$n');
    try {
      await _ch.invokeMethod<bool>('stop');
    } catch (_) {
      // 服务可能已经被系统停掉了，停不了不算错
    }
    _log('[YQK-SCREEN] svc stop');
  }

  Future<bool> _fgOk() async {
    try {
      return await _ch.invokeMethod<bool>('fgState') ?? false;
    } catch (e) {
      _log('[YQK-SCREEN] fgState fail $e');
      return false;
    }
  }

  void _log(String s) {
    final void Function(String)? f = onLog;
    if (f != null) f(s);
  }
}
