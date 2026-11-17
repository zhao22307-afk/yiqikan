/// 目录浏览：面包屑 + 列表 + 分页 + 点文件播放（P11）。
///
/// 只做「看」：多账号切换器、收藏、批量下载都留给 M11。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/failure_text.dart';
import '../../core/utils/redact.dart';
import '../../data/db/app_database.dart';
import '../../data/netdisk/netdisk_account_store.dart';
import '../../data/netdisk/netdisk_adapter.dart';
import '../../domain/resolver.dart';
import '../../features/player/player_controller.dart' show PlayerMedia;
import '../../providers/app_providers.dart';
import '../../routing/routes.dart';
import '../../theme/app_theme.dart';

class NetdiskBrowsePage extends ConsumerStatefulWidget {
  const NetdiskBrowsePage({super.key, required this.accountId, this.accountName = ''});

  final String accountId;
  final String accountName;

  @override
  ConsumerState<NetdiskBrowsePage> createState() => _NetdiskBrowsePageState();
}

class _NetdiskBrowsePageState extends ConsumerState<NetdiskBrowsePage> {
  String _path = '/';
  List<RemoteEntry>? _rows;
  String? _error;
  bool _loading = true;
  bool _playing = false;
  NetdiskAdapter? _adapter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load('/'));
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _path = path;
    });
    try {
      if (_adapter == null) {
        final NetdiskAccountStore store = ref.read(netdiskStoreProvider);
        final Account? acc = await store.db.accountDao.byId(widget.accountId);
        if (acc == null) throw const NotFoundException();
        _adapter = await store.adapterFor(acc);
      }
      final List<RemoteEntry> rows = await _adapter!.list(path);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = FailureText.lineOf(e);
        _loading = false;
      });
    }
  }

  Future<void> _play(RemoteEntry entry) async {
    if (_playing) return;
    setState(() => _playing = true);
    try {
      final ResolvedUrl r = await _adapter!.resolve(entry);
      // 日志只打到 host+path，直链里的 auth_key/sign 不进日志（M6 硬要求）
      debugPrint('[YQK-NETDISK] play resolver=${r.resolver} url=${redactUrl(r.url)}');
      if (!mounted) return;
      await context.push<void>(
        Routes.player,
        extra: PlayerMedia(
          id: r.url,
          title: entry.name,
          url: r.url,
          sourceKind: 'netdisk',
          headers: r.headers,
        ),
      );
    } on Object catch (e) {
      debugPrint('[YQK-NETDISK] play 失败：$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(FailureText.lineOf(e)),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  List<({String label, String path})> get _crumbs {
    final List<({String label, String path})> out = <({String label, String path})>[
      (label: '根目录', path: '/'),
    ];
    if (_path == '/' || _path.isEmpty) return out;
    final List<String> parts = _path.split('/').where((String s) => s.isNotEmpty).toList();
    String acc = '';
    for (final String p in parts) {
      acc = '$acc/$p';
      out.add((label: p, path: acc));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accountName.isEmpty ? '浏览' : widget.accountName),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(_path),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildCrumbs(),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildCrumbs() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        children: <Widget>[
          for (int i = 0; i < _crumbs.length; i++) ...<Widget>[
            if (i > 0)
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(Icons.chevron_right, size: 16, color: AppColors.textDim),
                ),
              ),
            TextButton(
              onPressed: () => _load(_crumbs[i].path),
              child: Text(
                _crumbs[i].label,
                style: AppText.sub.copyWith(
                  color: i == _crumbs.length - 1 ? AppColors.text : AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final String? err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_off, size: 40, color: AppColors.textDim),
              const SizedBox(height: AppSpace.sm),
              Text(err, textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppColors.textSub)),
              const SizedBox(height: AppSpace.md),
              OutlinedButton(onPressed: () => _load(_path), child: const Text('再试一次')),
            ],
          ),
        ),
      );
    }
    final List<RemoteEntry> rows = _rows ?? const <RemoteEntry>[];
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.folder_open, size: 36, color: AppColors.textDim),
            SizedBox(height: AppSpace.xs),
            Text('这个目录是空的', style: AppText.sub),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (BuildContext _, int _) => const Divider(height: 1),
      itemBuilder: (BuildContext c, int i) {
        final RemoteEntry e = rows[i];
        return ListTile(
          leading: Icon(
            e.isDir ? Icons.folder : _iconFor(e.name),
            color: e.isDir ? AppColors.warn : AppColors.primary,
          ),
          title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body),
          subtitle: e.isDir
              ? null
              : Text(
                  e.sizeText.isEmpty ? (e.extra['content-type'] ?? '') : e.sizeText,
                  style: AppText.label.copyWith(color: AppColors.textDim),
                ),
          trailing: e.isDir
              ? Icon(Icons.chevron_right, size: 18, color: AppColors.textDim)
              : (_playing
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.play_circle_outline, size: 20, color: AppColors.primary)),
          onTap: e.isDir
              ? () => _load('${_path == '/' ? '' : _path}/${e.name}')
              : () => _play(e),
        );
      },
    );
  }

  IconData _iconFor(String name) {
    final String n = name.toLowerCase();
    if (n.endsWith('.mp4') || n.endsWith('.mkv') || n.endsWith('.ts') || n.endsWith('.m3u8')) {
      return Icons.movie_outlined;
    }
    if (n.endsWith('.ass') || n.endsWith('.srt') || n.endsWith('.vtt')) {
      return Icons.subtitles_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}