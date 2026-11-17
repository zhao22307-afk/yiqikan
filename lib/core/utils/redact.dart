/// 日志脱敏工具（M6 硬要求）。
///
/// 网盘直链长这样：`https://cdn.example.com/file.mp4?auth_key=1759...&sign=abc123`
/// `auth_key` / `sign` 本身就是凭据，**不能进日志**。
/// 这里只保留 `scheme://host/path`，query 与 fragment 一律丢掉。
library;

/// 把 URL 压成「能定位但不含凭据」的形态。
///
/// - 保留：scheme、host（含端口）、path
/// - 丢弃：query、fragment、userInfo（`user:pass@`）
/// - 解析不了时返回固定占位，不把原串回显（原串里可能就带 token）
String redactUrl(String url) {
  if (url.isEmpty) return '<空地址>';
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    // 相对路径/本地文件路径：只要不是 http(s)，就没有 query 泄密风险
    if (url.startsWith('/') || url.startsWith('file:')) {
      return url.split('?').first;
    }
    return '<无法解析的地址>';
  }
  final String scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
  final String path = uri.path.isEmpty ? '/' : uri.path;
  return '$scheme://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$path';
}

/// 只留协议+主机，连路径都不给（用于「只想知道打到哪台机器」的日志）。
String redactHost(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '<无法解析的地址>';
  return '${uri.scheme}://${uri.host}';
}
