/// 全站统一异常（06 §3.3）。
///
/// 规矩：
/// - 每一条都能直接 `toString()` 给用户看，不许把 `SocketException: ...` 这种原始文本漏到界面上；
/// - [cause] 只进日志（AppLog），不进 UI；
/// - 子类表达"下一步该干什么"，不是技术分类。
library;

/// 所有业务异常的根。
class AppException implements Exception {
  const AppException(this.userMessage, {this.cause, this.actionHint});

  /// 给用户看的中文一句话
  final String userMessage;

  /// 原始异常/错误码，只用于日志
  final Object? cause;

  /// 可选：下一步动作提示（例如「去「片源」里扫码登录」）
  final String? actionHint;

  /// 界面上直接显示这一行
  String get display => actionHint == null ? userMessage : '$userMessage（$actionHint）';

  @override
  String toString() => '$runtimeType: $userMessage${cause == null ? '' : ' | cause=$cause'}';
}

/// 网络不可达 / DNS 失败 / 连接被拒
class NetworkException extends AppException {
  const NetworkException({Object? cause})
      : super('网络看起来不通，检查一下 Wi-Fi 或换个网络再试', cause: cause);
}

/// 请求超时
class RequestTimeoutException extends AppException {
  const RequestTimeoutException({Object? cause})
      : super('等太久了，服务器一直没回话，稍后再试', cause: cause);
}

/// 服务器回了非 2xx
class HttpStatusException extends AppException {
  const HttpStatusException(this.statusCode, {Object? cause})
      : super('服务器返回 $statusCode，这个源可能不太对', cause: cause);

  final int statusCode;
}

/// 返回内容解析不了（不是预期结构）
class ParseException extends AppException {
  const ParseException(String what, {Object? cause})
      : super('$what 的内容看不懂，可能这个源换了格式', cause: cause);
}

/// 源地址本身有问题（缺协议、不是 http/https、缺 api 路径）
class InvalidSourceException extends AppException {
  const InvalidSourceException(String reason) : super('这个源地址填得不对：$reason');
}

/// 明确"还没实现"，不许用空方法或 null 冒充
class UnsupportedException extends AppException {
  const UnsupportedException(this.what)
      : super('$what 还没做，这一档解析暂时用不了');

  final String what;
}

/// 需要登录（Cookie 缺失或过期）
class AuthRequiredException extends AppException {
  const AuthRequiredException({this.expired = false, Object? cause})
      : super(
          expired ? '登录状态过期了，重新登录一次' : '这个源需要登录才能看',
          cause: cause,
          actionHint: '去「片源」里登录',
        );

  final bool expired;
}

/// 地区限制（B 站 -10403）
class RegionLockedException extends AppException {
  const RegionLockedException({Object? cause})
      : super('这个内容只在大陆地区能看', cause: cause);
}

/// 风控（B 站 -352）
class RiskControlException extends AppException {
  const RiskControlException({Object? cause})
      : super('请求被源站风控拦了，过一会儿再试', cause: cause);
}

/// 版权 / 大会员（B 站 87007 / 87008）——和地区限制一样属于「不可恢复」，要落库停刷
class ContentLockedException extends AppException {
  const ContentLockedException({Object? cause})
      : super('这个内容需要会员或已下架，换个源试试', cause: cause);
}

/// 资源不存在（404 / B 站 -404）
class NotFoundException extends AppException {
  const NotFoundException({Object? cause}) : super('没找到这个内容', cause: cause);
}

/// 全部解析档位都失败：带上每一档的原因，UI 可展开
class ResolveFailedException extends AppException {
  ResolveFailedException(this.stageErrors)
      : super('这个链接暂时解析不了', actionHint: '展开看看每一档为什么失败');

  /// 档位名 → 失败原因（人话）
  final Map<String, String> stageErrors;

  @override
  String toString() =>
      'ResolveFailedException: $userMessage | ${stageErrors.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join('; ')}';
}

/// 网盘凭据过期（HTTP 401 / 平台自己的 code=401）
///
/// 与 [ResolveException] 分开是硬要求：这个要**跳登录**，那个要**重试**。
/// 不许 catch 住当成「空列表」——空目录和掉登录对用户是两件完全不同的事。
class AuthExpiredException extends AppException {
  const AuthExpiredException({Object? cause, String? hint})
      : super('登录状态过期了，重新登录一下',
            cause: cause, actionHint: hint ?? '去设置里重新登录这个网盘');
}

/// 直链拿不到（接口通了、凭据有效，但平台没给可播地址）
///
/// 常见原因：源文件被删、需要 VIP、平台临时限流。**可以重试**，不用重新登录。
class ResolveException extends AppException {
  const ResolveException({Object? cause, String? hint})
      : super(
          '这个文件暂时拿不到直链',
          cause: cause,
          actionHint: hint ?? '过一会儿再试，或者换个文件',
        );
}
