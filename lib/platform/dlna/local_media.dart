import 'package:dio/dio.dart';

/// M10 D 组：局域网媒体库（客户端）。
///
/// 服务端两条路由（Api.java）：
///   - `GET /local/media?path=<dir>`：列目录里的视频；
///   - `GET /local/media/play?path=<abs>`：直出，支持 Range（播放器要能拖）。
///
/// 权限：Android 13+ 要 READ_MEDIA_VIDEO，12 及以下要 READ_EXTERNAL_STORAGE。
/// 服务端会替我们检查（没权限返回 `permission denied`），客户端再兜一次提示。

class LocalMediaItem {
  LocalMediaItem({
    required this.name,
    required this.path,
    required this.size,
    required this.mtime,
  });

  final String name;
  final String path;
  final int size;
  final int mtime;

  String get sizeText {
    if (size <= 0) return '';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  String toString() => '$name ($sizeText)';
}

class LocalMediaResult {
  LocalMediaResult({
    required this.ok,
    required this.items,
    this.dirs = const <LocalMediaDir>[],
    this.detail = '',
    this.path = '',
    this.parent = '',
  });

  final bool ok;
  final List<LocalMediaItem> items;

  /// E6 B 组：同级的子目录（`/local/media` 的 `dirs`，老服务端没有就是空）
  final List<LocalMediaDir> dirs;
  final String detail;
  final String path;
  final String parent;
}

/// 一个子目录
class LocalMediaDir {
  const LocalMediaDir({required this.name, required this.path});

  final String name;
  final String path;

  @override
  String toString() => '$name/';
}

class LocalMediaClient {
  LocalMediaClient(this.base);

  /// 例如 `http://127.0.0.1:8080`
  final String base;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Future<LocalMediaResult> list({String path = '/sdcard/Movies'}) async {
    try {
      final Response<dynamic> r = await _dio
          .get('$base/local/media', queryParameters: <String, dynamic>{'path': path});
      final dynamic data = r.data;
      if (data is! Map) {
        return LocalMediaResult(ok: false, items: const <LocalMediaItem>[], detail: 'bad body');
      }
      final bool ok = data['success'] == true;
      final String detail = '${data['detail'] ?? ''}';
      final List<LocalMediaItem> items = <LocalMediaItem>[];
      final dynamic raw = data['items'];
      if (raw is List) {
        for (final dynamic e in raw) {
          if (e is! Map) continue;
          items.add(LocalMediaItem(
            name: '${e['name'] ?? ''}',
            path: '${e['path'] ?? ''}',
            size: e['size'] is num ? (e['size'] as num).toInt() : 0,
            mtime: e['mtime'] is num ? (e['mtime'] as num).toInt() : 0,
          ));
        }
      }
      final List<LocalMediaDir> dirs = <LocalMediaDir>[];
      final dynamic rawDirs = data['dirs'];
      if (rawDirs is List) {
        for (final dynamic e in rawDirs) {
          if (e is! Map) continue;
          final String name = '${e['name'] ?? ''}';
          final String path = '${e['path'] ?? ''}';
          if (name.isEmpty || path.isEmpty) continue;
          dirs.add(LocalMediaDir(name: name, path: path));
        }
      }
      return LocalMediaResult(
        ok: ok,
        items: items,
        dirs: dirs,
        detail: detail,
        path: '${data['path'] ?? path}',
        parent: '${data['parent'] ?? ''}',
      );
    } catch (e) {
      return LocalMediaResult(ok: false, items: const <LocalMediaItem>[], detail: '$e');
    }
  }

  /// 可播放地址（服务端直出，支持 Range）
  String playUrl(String path) =>
      '$base/local/media/play?path=${Uri.encodeQueryComponent(path)}';
}
