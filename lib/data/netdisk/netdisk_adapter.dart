/// 网盘适配器统一接口（04 §10.1 / 15 C 域）。
///
/// 四家（WebDAV / AList / Emby / 后续夸克 115 123 天翼）都实现它，
/// 上层浏览页只认这套接口，不认平台差异。
library;

import '../../core/errors/app_exception.dart';
import '../../domain/resolver.dart';

/// 一家网盘的标识。`prefValue` 落 PrefKeys 用，`label` 上界面。
enum NetdiskKind {
  webdav('webdav', 'WebDAV'),
  alist('alist', 'AList'),
  emby('emby', 'Emby'),
  quark('quark', '夸克'),
  pan115('pan115', '115'),
  pan123('pan123', '123 云盘'),
  tianyi('tianyi', '天翼云盘');

  const NetdiskKind(this.prefValue, this.label);

  final String prefValue;
  final String label;

  static NetdiskKind parse(String raw) => NetdiskKind.values.firstWhere(
        (NetdiskKind k) => k.prefValue == raw,
        orElse: () => NetdiskKind.webdav,
      );
}

/// 目录里的一项。`id` 是**平台自己认的标识**，不是路径。
class RemoteEntry {
  const RemoteEntry({
    required this.id,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.mtime,
    this.thumb,
    this.extra = const <String, String>{},
  });

  final String id;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? mtime;
  final String? thumb;

  /// 平台特有字段（WebDAV 的 contenttype、AList 的 sign/provider、Emby 的 RunTimeTicks…）
  final Map<String, String> extra;

  /// 人话大小，列表里直接用
  String get sizeText {
    if (isDir) return '';
    if (size <= 0) return '';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double v = size.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return i == 0 ? '${v.toStringAsFixed(0)}${units[i]}' : '${v.toStringAsFixed(1)}${units[i]}';
  }

  @override
  String toString() => 'RemoteEntry($id, $name, dir=$isDir, size=$size)';
}

/// 凭据里的非敏感部分（真正敏感的值只存在 SecureStore，不进这个对象）。
class NetdiskAccountInfo {
  const NetdiskAccountInfo({
    required this.kind,
    required this.displayName,
    this.endpoint = '',
    this.extra = const <String, String>{},
  });

  final NetdiskKind kind;
  final String displayName;

  /// 服务地址（WebDAV/AList/Emby 用；共用码头时是用户填的 baseUrl）
  final String endpoint;
  final Map<String, String> extra;
}

/// 四家网盘的共同契约。
///
/// 规矩：
/// - 401 / code=401 → 抛 [AuthExpiredException]（上层跳登录）
/// - 凭据有效但拿不到直链 → 抛 [ResolveException]（上层可重试）
/// - **绝不** catch 住返回空列表：空目录和掉登录必须能区分
abstract class NetdiskAdapter {
  NetdiskAdapter({required this.account});

  /// 由各子类固定返回自己的类型（不放进构造参数，避免每条适配器都要传一遍）
  NetdiskKind get kind;

  final NetdiskAccountInfo account;

  String get displayName => account.displayName;

  /// 凭据是否还有效（301/401 都会抛 [AuthExpiredException]）
  Future<bool> verify();

  /// 列目录。`path` 为空或 `/` 表示根。
  Future<List<RemoteEntry>> list(String path);

  /// 拿可播直链。必须带平台要求的 headers（Cookie / Referer / Authorization）。
  Future<ResolvedUrl> resolve(RemoteEntry entry);

  /// 把凭据写进 SecureStore（实现里自己拼 key，见 03 §5）
  Future<void> saveCredential();

  /// 删掉凭据（退出登录）
  Future<void> clearCredential();

  /// 这条地址要不要走 AList/Emby 的反代/转码；默认不需要
  bool get needsProxy => false;
}
