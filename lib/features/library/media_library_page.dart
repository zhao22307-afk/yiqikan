import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/player/player_controller.dart';
import '../../platform/dlna/local_media.dart';
import '../../routing/routes.dart';
import '../../theme/app_colors.dart';

/// F3 媒体库（10 号 :141）：扫本机目录，可进子目录、可搜、可播。
///
/// 数据来源是现成的 `/local/media`（E3 D 组做的服务端路由），
/// 播放入口也复用现成的 `Routes.player` —— 这里不写播放器。
class MediaLibraryPage extends StatefulWidget {
  const MediaLibraryPage({super.key, this.startPath = '/sdcard/Movies'});

  final String startPath;

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  static const String _base = 'http://127.0.0.1:8080';

  final LocalMediaClient _client = LocalMediaClient(_base);
  final TextEditingController _search = TextEditingController();

  late String _path = widget.startPath;
  List<LocalMediaItem> _items = const <LocalMediaItem>[];
  List<LocalMediaDir> _dirs = const <LocalMediaDir>[];
  bool _loading = true;
  bool _denied = false;
  String _detail = '';
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_ensurePermissionThenLoad());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _ensurePermissionThenLoad() async {
    Permission perm = Permission.videos;
    if (!await perm.isGranted) {
      final PermissionStatus s = await perm.request();
      if (!s.isGranted) {
        // Android 12 及以下没有「视频」分组，退回「存储」
        perm = Permission.storage;
        if (!await perm.isGranted) {
          final PermissionStatus s2 = await perm.request();
          if (!s2.isGranted) {
            debugPrint('[YQK-MEDIA] ui permission denied perm=$perm status=$s2');
            if (!mounted) return;
            setState(() {
              _denied = true;
              _loading = false;
            });
            return;
          }
        }
      }
    }
    await _load(_path);
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    final LocalMediaResult res = await _client.list(path: path);
    debugPrint('[YQK-MEDIA] list path=${res.path} ok=${res.ok} '
        'n=${res.items.length} dirs=${res.dirs.length} detail=${res.detail}');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = res.detail;
      if (res.ok) {
        _path = res.path.isEmpty ? path : res.path;
        _items = res.items;
        _dirs = res.dirs;
      } else {
        _denied = res.detail.contains('permission');
        _items = const <LocalMediaItem>[];
        _dirs = const <LocalMediaDir>[];
      }
    });
  }

  void _openItem(LocalMediaItem it) {
    final String url = _client.playUrl(it.path);
    debugPrint('[YQK-MEDIA] open path=${it.path} url=$url');
    unawaited(context.push<Object?>(
      Routes.player,
      extra: PlayerMedia(
        id: 'local_${it.path.hashCode}',
        title: it.name,
        url: url,
        sourceKind: 'local',
      ),
    ));
  }

  void _up() {
    final List<String> parts =
        _path.split('/').where((String s) => s.isNotEmpty).toList();
    if (parts.length <= 1) return; // 最低到 /sdcard，再往上没意义
    parts.removeLast();
    unawaited(_load('/${parts.join('/')}'));
  }

  List<LocalMediaItem> get _visible {
    if (_query.isEmpty) return _items;
    final String q = _query.toLowerCase();
    return _items
        .where((LocalMediaItem it) => it.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: '上一级',
          icon: const Icon(Icons.arrow_upward),
          onPressed: _loading ? null : _up,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => unawaited(_load(_path)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: <Widget>[
                Icon(Icons.folder_open, size: 16, color: AppColors.textSub),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: AppColors.textSub, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (String v) => setState(() => _query = v.trim()),
              style: TextStyle(color: AppColors.text, fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜文件名…',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_denied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('没有读取权限，去设置里开启',
                style: TextStyle(color: AppColors.textSub)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(openAppSettings()),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
    }
    final List<LocalMediaItem> items = _visible;
    if (_dirs.isEmpty && items.isEmpty) {
      return Center(
        child: Text(
          _detail.isEmpty ? '这个目录没有视频文件' : '这个目录没有视频文件（$_detail）',
          style: TextStyle(color: AppColors.textSub),
        ),
      );
    }
    return ListView.separated(
      itemCount: _dirs.length + items.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) {
        if (i < _dirs.length) {
          final LocalMediaDir d = _dirs[i];
          return ListTile(
            leading: Icon(Icons.folder, color: AppColors.textSub),
            title: Text(d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text)),
            subtitle: Text('目录',
                style: TextStyle(color: AppColors.textSub, fontSize: 12)),
            onTap: () => unawaited(_load(d.path)),
          );
        }
        final LocalMediaItem it = items[i - _dirs.length];
        return ListTile(
          leading: Icon(Icons.movie_outlined, color: AppColors.textSub),
          title: Text(it.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text)),
          subtitle: Text(it.sizeText,
              style: TextStyle(color: AppColors.textSub, fontSize: 12)),
          trailing: TextButton(
            onPressed: () => _openItem(it),
            child: const Text('播'),
          ),
          onTap: () => _openItem(it),
        );
      },
    );
  }
}