import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/deeplink/parse.dart';
import '../../theme/app_theme.dart';

/// 扫码加房：进页面就开摄像头，扫到第一个能解析成房间码的条码就 pop 回 code。
///
/// 只扫一次是刻意的：连着扫会把"刚识别完还没 pop 完"的第二帧也吃进来，
/// 结果弹两次页面、进两个房。[DetectionSpeed.noDuplicates] 由 controller 兜一层，
/// 页面自己再用 [_handled] 兜一层。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.debugImagePath});

  /// 仅调试/验收用：不立刻开摄像头，先识别这张图（真机上没法用摄像头扫一张图）。
  final String? debugImagePath;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _checking = true;
  bool _granted = false;
  bool _handled = false;
  DateTime? _lastToast;

  @override
  void initState() {
    super.initState();
    if (widget.debugImagePath != null) {
      // 喂图验收不碰摄像头，直接按"有权限"渲染，免得被权限面板盖住
      _checking = false;
      _granted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _analyzeImage(widget.debugImagePath!);
      });
      return;
    }
    _askPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _askPermission() async {
    PermissionStatus s = await Permission.camera.status;
    if (!s.isGranted) s = await Permission.camera.request();
    if (!mounted) return;
    debugPrint('[YQK-SCAN] camera permission=$s');
    setState(() {
      _checking = false;
      _granted = s.isGranted;
    });
  }

  Future<void> _analyzeImage(String path) async {
    try {
      final BarcodeCapture? cap = await _controller.analyzeImage(path);
      final List<Barcode> codes = cap?.barcodes ?? const <Barcode>[];
      debugPrint('[YQK-SCAN] analyze image=$path codes=${codes.length}');
      _onBarcodes(codes);
    } on Object catch (e) {
      debugPrint('[YQK-SCAN] analyze failed: $e');
      _notRoomCode();
    }
  }

  void _onDetect(BarcodeCapture capture) => _onBarcodes(capture.barcodes);

  /// 一帧里可能有好几个条码：取第一个能用的，都不行就提示一次、继续扫。
  void _onBarcodes(List<Barcode> codes) {
    if (_handled || !mounted) return;
    for (final Barcode b in codes) {
      final String? raw = b.rawValue;
      final RoomLink? link = parseScanText(raw);
      debugPrint('[YQK-SCAN] raw=${raw ?? '(null)'} -> ${link ?? '(不是进房码)'}');
      if (link != null) {
        _handled = true;
        Navigator.of(context).pop<String>(link.code);
        return;
      }
    }
    _notRoomCode();
  }

  void _notRoomCode() {
    if (!mounted) return;
    final DateTime now = DateTime.now();
    // 摄像头一秒能给十几帧，提示要节流，不然 SnackBar 会连成一串
    if (_lastToast != null && now.difference(_lastToast!).inMilliseconds < 1500) {
      return;
    }
    _lastToast = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这个二维码不是进房码')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码加房')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_granted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.no_photography_outlined,
                  size: 40, color: AppColors.textDim),
              const SizedBox(height: AppSpace.sm),
              Text('需要相机权限才能扫码', style: AppText.body),
              const SizedBox(height: AppSpace.md),
              FilledButton(
                onPressed: () => openAppSettings(),
                child: const Text('去设置'),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.debugImagePath != null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (BuildContext ctx, MobileScannerException e) {
            debugPrint('[YQK-SCAN] scanner error: ${e.errorCode} ${e.errorDetails}');
            return Center(
              child: Text('摄像头打不开，检查一下有没有被别的应用占着',
                  textAlign: TextAlign.center, style: AppText.body),
            );
          },
        ),
        // 取景框只是个视觉参照，不参与识别
        IgnorePointer(
          child: Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 仅调试构建可用：`/scan?image=/sdcard/x.png` 直接识别一张图。
@visibleForTesting
bool get scanImageHookEnabled => kDebugMode;