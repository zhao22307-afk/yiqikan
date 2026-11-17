/// 失败文案（15 §B20 / 04 §9.2）。
///
/// 规矩：任何异常进到 UI 前必须过这一层，只输出「一句中文人话 + 一个能做的事」，
/// 不许把 `SocketException: ...`、错误码、stacktrace 漏给用户。
library;

import 'app_exception.dart';

/// 五类用户能理解的失败原因（15 §B20）
enum FailureKind {
  /// 无网络：Wi-Fi / 数据断了
  offline,

  /// 源失效：域名挂了、404、源站搬家
  sourceDown,

  /// 版权限制：地区限制、会员专享
  copyright,

  /// 需登录：Cookie 缺失或过期、风控
  needLogin,

  /// 格式不支持：容器/编码放不了、页面结构变了
  unsupportedFormat,

  /// 兜底
  unknown,
}

/// 一类失败对应的一句话 + 一个建议
class FailureText {
  const FailureText(this.kind, this.message, this.hint);

  final FailureKind kind;
  final String message;
  final String hint;

  /// 界面上直接显示这一行
  String get display => '$message（$hint）';

  static const FailureText offline =
      FailureText(FailureKind.offline, '网络不通，检查一下 WiFi', '连上再试一次');
  static const FailureText sourceDown =
      FailureText(FailureKind.sourceDown, '这个源连不上，换个源试试', '也可以去「片源」里检查一下它');
  static const FailureText copyright =
      FailureText(FailureKind.copyright, '该内容有版权限制，换个源', '本站只播你有权看的内容');
  static const FailureText needLogin =
      FailureText(FailureKind.needLogin, '需要登录才能看，去设置里登录', '登录后再点一次');
  static const FailureText unsupportedFormat =
      FailureText(FailureKind.unsupportedFormat, '这个格式暂时放不了', '换个源或换个清晰度');
  static const FailureText unknown =
      FailureText(FailureKind.unknown, '这个链接暂时解析不了', '换个源试试');

  /// 把任意异常/错误翻成五类之一
  static FailureText of(Object error) {
    if (error is FailureText) return error;
    if (error is NetworkException || error is RequestTimeoutException) {
      return offline;
    }
    if (error is AuthRequiredException || error is RiskControlException) {
      return needLogin;
    }
    if (error is RegionLockedException) return copyright;
    if (error is UnsupportedException || error is ParseException) {
      return unsupportedFormat;
    }
    if (error is InvalidSourceException ||
        error is NotFoundException ||
        error is HttpStatusException) {
      return sourceDown;
    }
    if (error is ResolveFailedException) {
      // 每一档都失败：按出现最多的那类原因给一句话
      for (final String reason in error.stageErrors.values) {
        if (reason.contains('网络')) return offline;
        if (reason.contains('版权') || reason.contains('地区')) return copyright;
        if (reason.contains('登录') || reason.contains('风控')) return needLogin;
        if (reason.contains('格式') || reason.contains('看不懂')) {
          return unsupportedFormat;
        }
      }
      return sourceDown;
    }
    if (error is AppException) return unknown;
    return unknown;
  }

  /// 一行中文（UI 直接用这个）
  static String lineOf(Object error) => of(error).message;

  /// 一句话 + 建议
  static String detailOf(Object error) => of(error).display;
}
