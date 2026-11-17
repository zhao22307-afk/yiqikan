import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../providers/app_providers.dart';
import '../../routing/routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../player/player_controller.dart';

/// F4 播放列表（10 号 :142）：自建多个列表，列表内可拖排序。
///
/// 表结构见 tables.dart 的 `Playlists`：列表名就是 `name` 列，条目一行一条，
/// 顺序靠 `sortIndex`；空列表用一条 `mediaUrl=''` 的占位行表示（不显示、不计条数）。
class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  AppDatabase get _db => ref.read(appDatabaseProvider);

  List<PlaylistSummary> _lists = const <PlaylistSummary>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<PlaylistSummary> l = await _db.playlistDao.listNames();
    if (!mounted) return;
    setState(() {
      _lists = l;
      _loading = false;
    });
    debugPrint('[YQK-PL] lists n=${l.length} '
        '${l.map((PlaylistSummary s) => '${s.name}:${s.count}').join(',')}');
  }

  Future<void> _create() async {
    final String name = await _askName('新建列表', '');
    if (name.isEmpty) return;
    final bool ok = await _db.playlistDao.create(name);
    debugPrint('[YQK-PL] create name=$name ok=$ok');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('同名列表已存在')));
    }
    await _load();
  }

  Future<void> _rename(PlaylistSummary s) async {
    final String to = await _askName('重命名列表', s.name);
    if (to.isEmpty || to == s.name) return;
    final bool ok = await _db.playlistDao.rename(s.name, to);
    debugPrint('[YQK-PL] rename from=${s.name} to=$to ok=$ok');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('同名列表已存在')));
    }
    await _load();
  }

  Future<void> _remove(PlaylistSummary s) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('删掉「${s.name}」？'),
        content: Text('列表里的 ${s.count} 条会一起删掉，片子本身不受影响。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('再想想')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (go != true) return;
    final int n = await _db.playlistDao.remove(s.name);
    debugPrint('[YQK-PL] remove name=${s.name} rows=$n');
    await _load();
  }

  Future<String> _askName(String title, String init) async {
    final TextEditingController c = TextEditingController(text: init);
    final String? v = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '列表名，如「周末片单」'),
          onSubmitted: (String v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(''), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text),
              child: const Text('确定')),
        ],
      ),
    );
    c.dispose();
    return (v ?? '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _lists.isEmpty
            ? _empty()
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _lists.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext c, int i) {
                  final PlaylistSummary s = _lists[i];
                  return ListTile(
                    leading: Icon(Icons.queue_music,
                        color: AppColors.accent),
                    title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${s.count} 条',
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      tooltip: '改名 / 删除',
                      icon: const Icon(Icons.more_horiz, size: 18),
                      onPressed: () => _menu(s),
                    ),
                    onLongPress: () => _menu(s),
                    onTap: () => unawaited(Navigator.of(context).push<Object?>(
                      MaterialPageRoute<Object?>(
                        builder: (_) => PlaylistDetailPage(name: s.name),
                      ),
                    )),
                  );
                },
              );

    final Widget fab = FloatingActionButton.extended(
      heroTag: 'pl_fab',
      onPressed: () => unawaited(_create()),
      icon: const Icon(Icons.add),
      label: const Text('新建列表'),
    );

    if (widget.embedded) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        floatingActionButton: fab,
        body: body,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('播放列表'), backgroundColor: AppColors.bg),
      floatingActionButton: fab,
      body: body,
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.queue_music, size: 40, color: AppColors.textDim),
          const SizedBox(height: 10),
          Text('还没有列表，右下角新建一个',
              style: AppText.sub.copyWith(color: AppColors.textDim)),
        ],
      ),
    );
  }

  Future<void> _menu(PlaylistSummary s) async {
    final String? act = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('改名'),
              onTap: () => Navigator.of(c).pop('rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('删除列表'),
              onTap: () => Navigator.of(c).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (act == 'rename') await _rename(s);
    if (act == 'delete') await _remove(s);
  }
}

/// 列表详情：拖排序（ReorderableListView）+ 左滑删（Dismissible）+ 点播。
class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({super.key, required this.name});

  final String name;

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  AppDatabase get _db => ref.read(appDatabaseProvider);

  List<Playlist> _items = const <Playlist>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<Playlist> l = await _db.playlistDao.items(widget.name);
    if (!mounted) return;
    setState(() {
      _items = l;
      _loading = false;
    });
    debugPrint('[YQK-PL] items name=${widget.name} n=${l.length} '
        'ids=${l.map((Playlist r) => r.id).join(',')}');
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final List<Playlist> next = List<Playlist>.of(_items);
    if (newIndex > oldIndex) newIndex -= 1;
    final Playlist row = next.removeAt(oldIndex);
    next.insert(newIndex, row);
    final String before = _items.map((Playlist r) => r.id).join(',');
    setState(() => _items = next);
    await _db.playlistDao
        .reorder(widget.name, next.map((Playlist r) => r.id).toList());
    debugPrint('[YQK-PL] reorder name=${widget.name} '
        'before=$before after=${next.map((Playlist r) => r.id).join(',')}');
  }

  Future<void> _remove(Playlist r) async {
    await _db.playlistDao.removeItem(r.id);
    debugPrint('[YQK-PL] removeItem id=${r.id} name=${widget.name}');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: AppColors.bg,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text('这个列表还是空的',
                      style: AppText.sub.copyWith(color: AppColors.textDim)),
                )
              : ReorderableListView.builder(
                  // 长按整行即可拖动（真机上手感更稳，不依赖右下角小图标的命中率）
                  buildDefaultDragHandles: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _items.length,
                  onReorder: (int a, int b) => unawaited(_reorder(a, b)),
                  itemBuilder: (BuildContext c, int i) {
                    final Playlist r = _items[i];
                    return Dismissible(
                      key: ValueKey<String>(r.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: AppColors.danger,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => unawaited(_remove(r)),
                      child: ListTile(
                        title: Text(
                          r.mediaTitle ?? r.mediaUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${i + 1} · ${r.mediaUrl}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: Icon(Icons.drag_handle,
                              color: AppColors.textDim),
                        ),
                        onTap: () => unawaited(context.push<Object?>(
                          Routes.player,
                          extra: PlayerMedia(
                            id: 'pl_${r.id}',
                            title: r.mediaTitle ?? '播放列表',
                            url: r.mediaUrl,
                            sourceKind: 'playlist',
                          ),
                        )),
                      ),
                    );
                  },
                ),
    );
  }
}