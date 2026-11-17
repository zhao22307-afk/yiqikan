import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../data/db/library_dao.dart';
import '../../features/player/player_controller.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../routing/routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../download/download_page.dart';
import 'danmaku_library_page.dart';
import 'history_timeline.dart';
import 'playlist_page.dart';
import 'stats_page.dart';

/// F1 收藏 / 稍后看 / 历史 三合一页（10 号 :135-151 B22 之外的内容管理第一批）。
///
/// 表结构没动：稍后看 = `favorites.tag='later'`，历史 = `history`。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.embedded = false});

  /// 首页底部导航里用：不再套一层 Scaffold/AppBar，只出 TabBar + 内容
  final bool embedded;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 5, vsync: this);
  late final LibraryDao _dao = LibraryDao(ref.read(appDatabaseProvider));
  late final AppDatabase _db = ref.read(appDatabaseProvider);

  List<Favorite> _favs = const <Favorite>[];
  List<Favorite> _later = const <Favorite>[];
  List<Favorite> _follows = const <Favorite>[];
  /// F5 标签：mediaUrl → 标签名列表（行内展示用）
  Map<String, List<String>> _tagsByMedia = const <String, List<String>>{};
  /// F5 标签：去重后的标签名（顶部筛选用）
  List<String> _tagNames = const <String>[];
  /// 当前选中的标签筛选（null = 不筛）
  String? _tagFilter;
  int _historyKey = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() {
      if (!_tab.indexIsChanging) unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Favorite> f = await _dao.listFavorites();
    final List<Favorite> l = await _dao.listWatchLater();
    final List<Favorite> fo = await _dao.listFollowing();
    final List<TagRow> tags = await _db.tagDao.all();
    final Map<String, List<String>> byMedia = <String, List<String>>{};
    final List<String> names = <String>[];
    for (final TagRow t in tags) {
      (byMedia[t.mediaUrl] ??= <String>[]).add(t.name);
      if (!names.contains(t.name)) names.add(t.name);
    }
    names.sort();
    if (!mounted) return;
    setState(() {
      _favs = f;
      _later = l;
      _follows = fo;
      _tagsByMedia = byMedia;
      _tagNames = names;
      if (_tagFilter != null && !names.contains(_tagFilter)) _tagFilter = null;
      _loading = false;
    });
    debugPrint('[YQK-LIB] list fav=${f.length} later=${l.length} '
        'follow=${fo.length} tags=${tags.length}');
  }

  /// 用现成的播放入口（不另写播放器）
  Future<void> _open({
    required String id,
    required String title,
    required String url,
    required String sourceKind,
    String? sourceId,
    String? poster,
  }) async {
    debugPrint('[YQK-LIB] open title=$title kind=$sourceKind');
    await context.push<Object?>(
      Routes.player,
      extra: PlayerMedia(
        id: id,
        title: title,
        url: url,
        sourceKind: sourceKind,
        sourceId: sourceId,
        poster: poster,
      ),
    );
    unawaited(_load());
  }

  Future<void> _openHistory(History h) => _open(
        id: h.id,
        title: h.title,
        url: h.url,
        sourceKind: h.sourceKind,
        sourceId: h.sourceId,
        poster: h.poster,
      );

  Future<void> _deleteFavorite(Favorite f) async {
    await _dao.removeFavorite(f.id);
    await _load();
  }

  Future<void> _clearFavorites() async {
    await _dao.clearFavorites();
    await _load();
  }

  Future<void> _deleteLater(Favorite f) async {
    await _dao.markWatchLater(LibraryMedia(
      title: f.title,
      url: f.url,
      sourceKind: f.sourceKind,
      sourceId: f.sourceId,
      poster: f.poster,
    ));
    await _load();
  }

  /// 收藏列表里把一条标成追番
  Future<void> _follow(Favorite f) async {
    final bool on = await _dao.markFollow(LibraryMedia(
      title: f.title,
      url: f.url,
      sourceKind: f.sourceKind,
      sourceId: f.sourceId,
      poster: f.poster,
    ));
    debugPrint('[YQK-FAV] follow on=$on url=${f.url}');
    await _load();
  }

  /// 追番条里取消追番（清 tag，行还在 → 回到收藏）
  Future<void> _unfollow(Favorite f) async {
    await _dao.unfollow(f.id);
    debugPrint('[YQK-FAV] follow on=false url=${f.url}');
    await _load();
  }

  Future<void> _clearHistory() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空观看历史？'),
        content: const Text('只删历史记录，收藏和稍后看不动。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _dao.clearHistory();
    if (!mounted) return;
    setState(() => _historyKey++);
  }

  TabBar _tabs(BuildContext context) {
    final L t = L.of(context);
    return TabBar(
      controller: _tab,
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.textSub,
      indicatorColor: AppColors.accent,
      tabs: <Widget>[
        Tab(text: t.libFavorites),
        const Tab(text: '稍后看'),
        Tab(text: t.libHistory),
        Tab(text: t.libDownload),
        const Tab(text: '列表'),
      ],
    );
  }

  Future<void> _clearCurrent() async {
    switch (_tab.index) {
      case 0:
        await _clearFavorites();
      case 2:
        await _clearHistory();
      case 3:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载请逐条删除')),
        );
      case 4:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('列表请逐条删除')),
        );
      default:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('稍后看请逐条删除')),
        );
    }
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return TabBarView(
      controller: _tab,
      children: <Widget>[
        _favList(),
        _laterList(),
        HistoryTimeline(
          key: ValueKey<int>(_historyKey),
          dao: _dao,
          onOpen: (History h) => unawaited(_openHistory(h)),
        ),
        Column(
          children: <Widget>[
            // F3 媒体库入口（放在下载 tab 顶部：不新开 tab，避免 TabBar 挤成 5 个）
            Material(
              color: AppColors.bg,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.video_library_outlined,
                    color: AppColors.textSub),
                title: Text('本机视频',
                    style: TextStyle(color: AppColors.text, fontSize: 14)),
                subtitle: Text('扫本机目录，可进子目录、可搜',
                    style: TextStyle(color: AppColors.textSub, fontSize: 11)),
                trailing: Icon(Icons.chevron_right, color: AppColors.textSub),
                onTap: () => unawaited(context.push<Object?>(
                  Routes.mediaLibrary,
                )),
              ),
            ),
            const Divider(height: 1),
            const Expanded(child: DownloadPage(embedded: true)),
          ],
        ),
        const PlaylistPage(embedded: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // 嵌在首页底部导航里：顶部只有一条标题行 + TabBar，不再套 Scaffold
      return Column(
        children: <Widget>[
          Material(
            color: AppColors.bg,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.page, AppSpace.sm, AppSpace.xs, 0),
                  child: Row(
                    children: <Widget>[
                      Text('我的',
                          style: TextStyle(
                              color: AppColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      // F11 弹幕库入口（从「我的」进 = 全部收藏，不按房间窄化）
                      IconButton(
                        tooltip: '弹幕库',
                        icon: Icon(Icons.subtitles_outlined,
                            color: AppColors.textSub),
                        onPressed: () => unawaited(
                            Navigator.of(context).push(MaterialPageRoute<Object?>(
                          builder: (BuildContext _) =>
                              const DanmakuLibraryPage(),
                        ))),
                      ),
                      // F6 观看统计入口（我的页顶部，任务书要求「图标按钮或第一张卡」）
                      IconButton(
                        tooltip: '观看统计',
                        icon: Icon(Icons.insights_outlined,
                            color: AppColors.textSub),
                        onPressed: () => unawaited(Navigator.of(context).push(
                          MaterialPageRoute<Object?>(
                            builder: (BuildContext _) => const StatsPage(),
                          ),
                        )),
                      ),
                      IconButton(
                        tooltip: '清空本页',
                        icon: Icon(Icons.delete_sweep_outlined,
                            color: AppColors.textSub),
                        onPressed: _loading ? null : () => unawaited(_clearCurrent()),
                      ),
                    ],
                  ),
                ),
                _tabs(context),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(L.of(context).tabLibrary),
        bottom: _tabs(context),
        actions: <Widget>[
          IconButton(
            tooltip: '观看统计',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => unawaited(Navigator.of(context).push(
              MaterialPageRoute<Object?>(
                builder: (BuildContext _) => const StatsPage(),
              ),
            )),
          ),
          IconButton(
            tooltip: '清空本页',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _loading ? null : () => unawaited(_clearCurrent()),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _favList() {
    final List<Favorite> shown = _tagFilter == null
        ? _favs
        : _favs
            .where((Favorite f) =>
                (_tagsByMedia[f.url] ?? const <String>[]).contains(_tagFilter))
            .toList();
    final Widget tail = shown.isEmpty
        ? Center(
            child: Text(
                _tagFilter == null
                    ? '还没有收藏，长按片子标题可以收藏'
                    : '没有带「$_tagFilter」标签的收藏',
                style: TextStyle(color: AppColors.textSub)),
          )
        : ListView.separated(
            itemCount: shown.length,
            separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int i) => _row(
              fav: shown[i],
              subtitle: _subtitleOf(shown[i]),
              tags: _tagsByMedia[shown[i].url] ?? const <String>[],
              onDelete: () => unawaited(_deleteFavorite(shown[i])),
              onFollow: () => unawaited(_follow(shown[i])),
              onTag: () => unawaited(_openTagDialog(shown[i])),
              onTap: () => unawaited(_open(
                id: shown[i].id,
                title: shown[i].title,
                url: shown[i].url,
                sourceKind: shown[i].sourceKind,
                sourceId: shown[i].sourceId,
                poster: shown[i].poster,
              )),
              index: i,
            ),
          );
    return Column(
      children: <Widget>[
        _followStrip(),
        _tagStrip(),
        Expanded(child: tail),
      ],
    );
  }

  /// 行副标题：tag 字段（收藏/追番）+ 自定义标签
  String _subtitleOf(Favorite f) {
    final String base = f.tag ?? '收藏';
    final List<String> ts = _tagsByMedia[f.url] ?? const <String>[];
    return ts.isEmpty ? base : '$base · ${ts.join(' / ')}';
  }

  /// 收藏 tab 顶部：标签筛选 Chip（有标签才显示）
  Widget _tagStrip() {
    if (_tagNames.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.xs, top: 6),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: _tagFilter == null,
              onSelected: (_) => _pickTag(null),
            ),
          ),
          for (final String n in _tagNames)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.xs, top: 6),
              child: ChoiceChip(
                label: Text(n),
                selected: _tagFilter == n,
                onSelected: (_) => _pickTag(_tagFilter == n ? null : n),
              ),
            ),
        ],
      ),
    );
  }

  void _pickTag(String? name) {
    setState(() => _tagFilter = name);
    final int n = name == null
        ? _favs.length
        : _favs
            .where((Favorite f) =>
                (_tagsByMedia[f.url] ?? const <String>[]).contains(name))
            .length;
    debugPrint('[YQK-TAG] filter name=${name ?? 'all'} n=$n');
  }

  /// 标签对话框：已有标签（可删）+ 输入框 + 添加
  Future<void> _openTagDialog(Favorite f) async {
    final TextEditingController input = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) {
          final List<TagRow> mine = _tagsByMedia[f.url] == null
              ? const <TagRow>[]
              : const <TagRow>[];
          return AlertDialog(
            title: const Text('标签'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(f.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textSub, fontSize: 12)),
                const SizedBox(height: AppSpace.sm),
                FutureBuilder<List<TagRow>>(
                  future: _db.tagDao.byMedia(f.url),
                  builder: (BuildContext c, AsyncSnapshot<List<TagRow>> snap) {
                    final List<TagRow> rows = snap.data ?? mine;
                    if (rows.isEmpty) {
                      return Text('还没有标签',
                          style: TextStyle(color: AppColors.textSub));
                    }
                    return Wrap(
                      spacing: AppSpace.xs,
                      children: <Widget>[
                        for (final TagRow t in rows)
                          InputChip(
                            label: Text(t.name),
                            onDeleted: () async {
                              await _db.tagDao.removeTag(t.id);
                              debugPrint('[YQK-TAG] remove id=${t.id} '
                                  'name=${t.name}');
                              await _load();
                              setLocal(() {});
                            },
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: input,
                  decoration: const InputDecoration(
                      isDense: true, hintText: '新标签，如「周更」'),
                  onSubmitted: (String v) async {
                    await _addTag(f, v);
                    input.clear();
                    setLocal(() {});
                  },
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () async {
                  await _addTag(f, input.text);
                  input.clear();
                  setLocal(() {});
                },
                child: const Text('添加'),
              ),
            ],
          );
        },
      ),
    );
    input.dispose();
  }

  Future<void> _addTag(Favorite f, String name) async {
    final String n = name.trim();
    if (n.isEmpty) return;
    final bool added = await _db.tagDao.addTag(f.url, n);
    debugPrint('[YQK-TAG] add name=$n new=$added url=${f.url}');
    await _load();
  }

  /// 收藏 tab 顶部：追番中 N 部（有才显示），横滑卡片
  Widget _followStrip() {
    if (_follows.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 96,
      color: AppColors.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text('追番中 ${_follows.length} 部',
                style: TextStyle(
                    color: AppColors.textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _follows.length,
              separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int i) {
                final Favorite f = _follows[i];
                return SizedBox(
                  width: 168,
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.surface3,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: InkWell(
                            onTap: () => unawaited(_open(
                              id: f.id,
                              title: f.title,
                              url: f.url,
                              sourceKind: f.sourceKind,
                              sourceId: f.sourceId,
                              poster: f.poster,
                            )),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(f.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.text, fontSize: 13)),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_horiz,
                              size: 18, color: AppColors.textSub),
                          onSelected: (String v) {
                            if (v == 'unfollow') unawaited(_unfollow(f));
                            if (v == 'del') unawaited(_deleteFavorite(f));
                          },
                          itemBuilder: (_) => const <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                                value: 'unfollow', child: Text('取消追番')),
                            PopupMenuItem<String>(value: 'del', child: Text('删除')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _laterList() {
    if (_later.isEmpty) {
      return Center(
        child: Text('还没有稍后看的片子',
            style: TextStyle(color: AppColors.textSub)),
      );
    }
    return ListView.separated(
      itemCount: _later.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) => _row(
        fav: _later[i],
        subtitle: '稍后看',
        onDelete: () => unawaited(_deleteLater(_later[i])),
        onTap: () => unawaited(_open(
          id: _later[i].id,
          title: _later[i].title,
          url: _later[i].url,
          sourceKind: _later[i].sourceKind,
          sourceId: _later[i].sourceId,
          poster: _later[i].poster,
        )),
        index: i,
      ),
    );
  }

  Widget _row({
    required Favorite fav,
    required String subtitle,
    required VoidCallback onDelete,
    required VoidCallback onTap,
    required int index,
    List<String> tags = const <String>[],
    VoidCallback? onFollow,
    VoidCallback? onTag,
  }) {
    return ListTile(
      leading: fav.poster == null || fav.poster!.isEmpty
          ? Container(
              width: 44,
              height: 60,
              color: AppColors.surface3,
              child: Icon(Icons.movie_outlined,
                  size: 20, color: AppColors.textSub),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                fav.poster!,
                width: 44,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 44,
                  height: 60,
                  color: AppColors.surface3,
                  child: Icon(Icons.movie_outlined,
                      size: 20, color: AppColors.textSub),
                ),
              ),
            ),
      title: Text(fav.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.text)),
      subtitle: Text(subtitle,
          style: TextStyle(color: AppColors.textSub, fontSize: 12)),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, color: AppColors.textSub),
        onSelected: (String v) {
          if (v == 'del') onDelete();
          if (v == 'follow') onFollow?.call();
          if (v == 'tag') onTag?.call();
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          if (onFollow != null)
            const PopupMenuItem<String>(value: 'follow', child: Text('追番')),
          if (onTag != null)
            const PopupMenuItem<String>(value: 'tag', child: Text('标签…')),
          const PopupMenuItem<String>(value: 'del', child: Text('删除')),
        ],
      ),
    );
  }
}