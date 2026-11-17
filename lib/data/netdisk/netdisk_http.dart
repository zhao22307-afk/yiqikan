/// 网盘公共小工具：UA、Referer、错误码归一化。
///
/// 四家网盘都是网页端接口，UA 必须像桌面浏览器，否则会 401/403；
/// 错误码统一映射成 AppException 子类（AuthExpired / Resolve / Parse）。
library;

import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';

/// 桌面浏览器 UA（各家后台都按这个认）
const String kDesktopUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// 统一的 Dio 超时（03 §11 的两个常量）
Dio newNetdiskDio({
  Duration connect = const Duration(seconds: 8),
  Duration read = const Duration(seconds: 20),
  Map<String, String>? baseHeaders,
}) {
  return Dio(
    BaseOptions(
      connectTimeout: connect,
      receiveTimeout: read,
      sendTimeout: read,
      headers: baseHeaders,
      // 4xx 也让我们自己读 body（各家的错误码都在 body 里）
      validateStatus: (int? code) => code != null && code < 600,
      followRedirects: true,
    ),
  );
}

/// 把 HTTP 状态翻成人话异常。401/403 一律当「需要重新登录」。
Never throwHttpStatus(int? status, {String what = '这个网盘'}) {
  if (status == 401 || status == 403) {
    throw const AuthExpiredException();
  }
  if (status == 404) {
    throw ResolveException(hint: '$what 说找不到这个文件');
  }
  throw AppException('$what 返回了 HTTP $status');
}

/// 把一家的业务 code 翻成异常；`codes` 是「登录失效」这一组业务码。
Never throwBizCode(int? code, {required Set<int> authCodes, String what = '这个网盘'}) {
  if (code != null && authCodes.contains(code)) {
    throw const AuthExpiredException();
  }
  throw ResolveException(hint: '$what 返回错误码 $code');
}
