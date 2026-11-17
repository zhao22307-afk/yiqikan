import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 把一条远端（或本地预览）屏幕 track 画满整个 video 区。
///
/// 只做「画」这一件事：尺寸、层级、显隐都由调用方决定。
/// `onResize` 报上来的宽高是真实帧尺寸——后台仍在推流时它是真值，
/// 若一直是 0x0 说明 track 没真正出帧，不要在外面硬编一个值糊过去。
class ScreenView extends StatefulWidget {
  const ScreenView({super.key, required this.track, this.onReady});

  final MediaStreamTrack track;

  /// 首帧尺寸回调（可能在多次 resize 时重复触发）。
  final void Function(int w, int h)? onReady;

  @override
  State<ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<ScreenView> {
  final RTCVideoRenderer _r = RTCVideoRenderer();
  MediaStream? _stream;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _r.initialize();
    // 该版本的 MediaStream 是抽象类，不能直接 new：
    // 用一个空流把这条 track 装进去，喂给 renderer。
    final MediaStream stream = await createLocalMediaStream('screen');
    await stream.addTrack(widget.track);
    _stream = stream;
    _r.srcObject = stream;
    _r.onResize = _reportSize;
    // 有的机型首帧早于 onResize 绑定，这里补报一次。
    _reportSize();
    if (mounted) setState(() {});
  }

  void _reportSize() {
    final int w = _r.value.width.toInt();
    final int h = _r.value.height.toInt();
    debugPrint('[YQK-SCREEN] view size ${w}x$h');
    if (w > 0 && h > 0) widget.onReady?.call(w, h);
  }

  @override
  void dispose() {
    _r.onResize = null;
    _r.srcObject = null;
    // 显式释放原生 Texture，否则换轨会泄漏一层。
    _r.dispose();
    // 只释放我们自己造的那个壳，track 的所有权在调用方（ScreenShare / 引擎）。
    final MediaStream? s = _stream;
    _stream = null;
    if (s != null) unawaited(s.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RTCVideoView(
      _r,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      mirror: false,
    );
  }
}
