import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// P3 探针：验证 QuickJS 能不能在本工程里跑起来。
///
/// 只做自检，不承载任何业务。真实调用失败时返回异常文本，不抛给上层。
class QjsProbe {
  QjsProbe._();

  static const MethodChannel _ch = MethodChannel('yiqikan/probe');

  /// 返回多行自检文本（eval / json / fn / throw / loop100），失败时以 `FATAL` 开头。
  static Future<String?> ping() async {
    try {
      final String? r = await _ch.invokeMethod<String>('quickjsPing');
      debugPrint('[YQK-QJS] probe result len=${r?.length ?? -1}');
      return r;
    } on MissingPluginException catch (e) {
      debugPrint('[YQK-QJS] no bridge: $e');
      return 'FATAL MissingPluginException: $e';
    } on PlatformException catch (e) {
      debugPrint('[YQK-QJS] platform error: ${e.code} ${e.message}');
      return 'FATAL PlatformException(${e.code}): ${e.message}';
    }
  }

  /// P3 第二步：drpy2 运行时（jar 里的 web.js）加载探针。
  ///
  /// 返回多行文本：read len / eval 结果或错误 / module 结果或错误 / typeof DRPY / heap。
  /// 只在片源页长按菜单里手动触发，不进启动路径。
  static Future<String?> drpy2() async {
    try {
      final String? r = await _ch.invokeMethod<String>('drpy2Probe');
      debugPrint('[YQK-DRPY] probe result len=${r?.length ?? -1}');
      return r;
    } on MissingPluginException catch (e) {
      debugPrint('[YQK-DRPY] no bridge: $e');
      return 'FATAL MissingPluginException: $e';
    } on PlatformException catch (e) {
      debugPrint('[YQK-DRPY] platform error: ${e.code} ${e.message}');
      return 'FATAL PlatformException(${e.code}): ${e.message}';
    }
  }
}
