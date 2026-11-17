import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/layout/breakpoints.dart';
import '../../data/db/app_database.dart';
import '../../data/sources/maccms.dart';
import '../../data/sources/hdmoli.dart';
import '../../data/sources/source_service.dart';
import '../../data/sources/tvbox_config.dart';
import '../../data/sources/tvbox_importer.dart';
import '../../platform/tvbox/tvbox_bridge.dart';
import '../../platform/tvbox/qjs_probe.dart';
import 'search_hit_card.dart';
import '../../domain/resolver.dart';
import '../../providers/app_providers.dart';
import '../../routing/routes.dart';
import '../../theme/app_theme.dart';
import '../player/bili_watch_page.dart';
import '../player/player_controller.dart';
import '../sniffer/sniff_page.dart';

/// P05 浏览（05 §3.3）：源列表 + 搜索 + 结果网格 + 点进播放
class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key, this.pickMode = false});

  /// 选片模式（房间内「换片源」用）：点卡片不 push 播放器，
  /// 而是把解析好的 PlayerMedia pop 回调用方。
  final bool pickMode;

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  final TextEditingController _keyword = TextEditingController();
  List<Source> _sources = <Source>[];
  List<SearchHit> _hits = <SearchHit>[];
  final Set<String> _searching = <String>{};
  bool _loadingSources = true;
  bool _searchingAll = false;
  String? _error;
  String _lastQuery = '';

  /// TVBox 配置里 js / py 两类（不导入，只置灰展示）
  List<TvboxSite> _tvboxUnavailable = <TvboxSite>[];

  /// F9 片源评分：sourceId → 1..5（没打分的源不在表里）
  Map<String, int> _scores = <String, int>{};

  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<void> _loadScores() async {
    final List<SourceRating> rows = await _db.ratingDao.all();
    if (!mounted) return;
    setState(() {
      _scores = <String, int>{
        for (final SourceRating r in rows) r.sourceId: r.score,
      };
    });
    debugPrint('[YQK-RATE] load n=${rows.length} '
        '${rows.map((SourceRating r) => '${r.sourceId}=${r.score}').join(',')}');
  }

  Future<void> _rate(Source s, int score) async {
    final int v = await _db.ratingDao.setScore(s.id, score);
    debugPrint('[YQK-RATE] set source=${s.id} score=$v');
    await _loadScores();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSources();
      _loadScores();
    });
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  SourceService get _service => ref.read(sourceServiceProvider);

  Future<void> _loadSources() async {
    setState(() => _loadingSources = true);
    try {
      // 内置源：第一次进来补一条 HDmoli（幂等，已有就跳过）
      await _service.seedBuiltins();
      final List<Source> list = await _service.list();
      // TVBox 配置里 js / py 两类不导入（没有引擎），但仍列出来置灰
      final List<TvboxSite> unavailable = await _loadUnavailableTvbox();
      if (!mounted) return;
      setState(() {
        _sources = list;
        _tvboxUnavailable = unavailable;
        _loadingSources = false;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSources = false;
        _error = e is AppException ? e.display : '片源列表读不出来';
      });
    }
  }

  /// P3 调试菜单：长按「片源」标题触发。只放探针，不放业务。
  Future<void> _showProbeMenu() async {
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('drpy2 加载探针'),
              subtitle: const Text('把 jar 里的 web.js 读进 QuickJS，看能不能编译'),
              onTap: () => Navigator.pop(ctx, 'drpy2'),
            ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('QuickJS 自检'),
              subtitle: const Text('eval / json / fn / throw / loop100'),
              onTap: () => Navigator.pop(ctx, 'qjs'),
            ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? out = pick == 'drpy2' ? await QjsProbe.drpy2() : await QjsProbe.ping();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        (out == null || out.isEmpty) ? '探针没有输出' : out,
        maxLines: 12,
        overflow: TextOverflow.ellipsis,
      ),
      duration: const Duration(seconds: 12),
    ));
  }

  /// 读内置配置里 js / py 两类（不导入，只展示「有但用不了」）
  Future<List<TvboxSite>> _loadUnavailableTvbox() async {
    try {
      final String raw = await rootBundle.loadString(TvboxImporter.assetKey);
      final List<TvboxSite> all = TvboxConfig.parse(raw);
      return all
          .where((TvboxSite s) => s.kind == 'js' || s.kind == 'py')
          .toList(growable: false);
    } on Object catch (e) {
      debugPrint('[YQK-TVBOX] load unavailable failed: $e');
      return const <TvboxSite>[];
    }
  }

  Future<void> _check(Source s) async {
    setState(() => _searching.add(s.id));
    final SourceHealth h = await _service.check(s);
    if (!mounted) return;
    setState(() => _searching.remove(s.id));
    await _loadSources();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(h.isDown
          ? '${s.name} 连不上${h.message == null ? '' : '：${h.message}'}'
          : '${s.name} ${h.health == 'ok' ? '正常' : '有点慢'}（${h.latencyMs}ms）'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _delete(Source s) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删掉这个源？'),
        content: Text('「${s.name}」删掉后要重新添加，搜索里就看不到它了。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删掉'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.remove(s.id);
    await _loadSources();
  }

  Future<void> _toggle(Source s, bool on) async {
    await _service.update(s, enabled: on);
    await _loadSources();
  }

  Future<void> _search() async {
    final String kw = _keyword.text.trim();
    if (kw.isEmpty) {
      setState(() => _error = '先输一个片名再搜');
      return;
    }
    setState(() {
      _searchingAll = true;
      _error = null;
      _lastQuery = kw;
    });
    try {
      final List<SearchHit> hits = await _service.search(kw);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searchingAll = false;
      });
      if (hits.isEmpty) {
        setState(() => _error = '没搜到「$kw」，换个词或加个源试试');
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _searchingAll = false;
        _error = e is AppException ? e.display : '搜索出了点意外，稍后再试';
      });
    }
  }

  /// 点一条结果：先解析成直链，再进播放页
  Future<void> _play(SearchHit hit) async {
    // 网页型片源（HDmoli 这一类）：搜索页只有作品，没有直链，
    // 得先拉详情拿线路/剧集，再交给嗅探页去取播放地址
    if (_isHtmlHit(hit)) {
      await _playHtml(hit);
      return;
    }
    // TVBox（csp_xxx）：同样是「搜索只有作品」，详情才给线路/剧集
    if (_isTvboxHit(hit)) {
      await _playTvbox(hit);
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String rawUrl;
    try {
      if (hit.item != null) {
        rawUrl = MacCmsParser.firstEpisodeUrl(hit.item!);
      } else if (hit.url != null) {
        rawUrl = hit.url!;
      } else {
        throw const UnsupportedException('这条结果的播放地址');
      }
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.display),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    messenger.showSnackBar(const SnackBar(
      content: Text('正在解析播放地址…'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
    await _openRaw(hit, rawUrl, messenger);
  }

  /// 拿到直链之后的公共段：Resolver → PlayerMedia → 播放页（TVBox / maccms / 直链共用）
  Future<void> _openRaw(
    SearchHit hit,
    String rawUrl,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      final ResolvedUrl r = await ref.read(resolverProvider).resolve(rawUrl);
      if (!mounted) return;
      // 第 39 轮：b 站的 playurl 给的是 DASH 分片（`*.m4s`，只有视频轨、没有 init 段），
      // 本机内核 prepare 直接返回 -1 → 播放器弹「这个源连不上」。
      // 这类地址不进原生播放器，直接交给 b 站自己的 H5 播放器。
      // 只看片源页（pickMode 不走这里）：房间换片源靠 media 帧同步，WebView 同步不了。
      if (!widget.pickMode &&
          rawUrl.contains('bilibili.com') &&
          _isBiliDash(r.url)) {
        messenger.hideCurrentSnackBar();
        await Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => BiliWatchPage(url: rawUrl, title: hit.title),
        ));
        return;
      }
      // 片单：把这条线路的剧集一起带进去，上一集/下一集/自动连播才有东西可走
      final List<PlayerMedia> playlist = _buildPlaylist(hit, rawUrl, r);
      final String currentId =
          playlist.isEmpty ? 'src_${hit.sourceId}' : playlist.first.id;
      final PlayerMedia media = PlayerMedia(
        id: currentId,
        title: hit.title,
        url: r.url,
        sourceKind: r.resolver,
        sourceId: hit.item?.id,
        poster: hit.poster.isEmpty ? null : hit.poster,
        headers: r.headers,
        playlist: playlist,
      );
      // 选片模式：把这一条交回调用方（房间内换片源），不进播放器。
      // 第 38 轮：连同整条线路的片单一起回传，否则房主换片后 hasNext=false、
      // D12 的 ended 永远走「跳过」。
      if (widget.pickMode) {
        if (!mounted) return;
        messenger.hideCurrentSnackBar();
        Navigator.of(context).pop(<String, Object?>{
          'media': media,
          'playlist': playlist,
        });
        return;
      }
      await context.push<Object?>(
        Routes.player,
        extra: media,
      );
    } on AppException catch (e) {
      // 第 39 轮：b 站解析失败（风控 / 失效 / 拿不到 playurl）时降级到 WebView，
      // 让 b 站自己的播放器去处理；MacCMS 等其它源保持原样弹错误，不兜底。
      if (!widget.pickMode && rawUrl.contains('bilibili.com')) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        await Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => BiliWatchPage(url: rawUrl, title: hit.title),
        ));
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(e.display),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// 网页型片源点开一条结果：详情 → 选线路/剧集 → 嗅探页取播放地址
  Future<void> _playHtml(SearchHit hit) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MacCmsItem? base = hit.item;
    if (base == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('这条结果没有作品信息'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    messenger.showSnackBar(const SnackBar(
      content: Text('正在读详情…'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));

    MacCmsItem item = base;
    if (item.lines.isEmpty) {
      try {
        item = await HdmoliSource.instance.detail(base.id);
      } on AppException catch (e) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(e.display),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    MacCmsEpisode? picked;
    if (item.lines.length == 1 && item.lines.first.episodes.length == 1) {
      picked = item.lines.first.episodes.first;
    } else {
      picked = await _pickEpisode(item);
    }
    if (picked == null || !mounted) return;

    final String page;
    try {
      page = HdmoliSource.instance.play(picked.url);
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.display),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (widget.pickMode) {
      messenger.showSnackBar(const SnackBar(
        content: Text('网页型片源要到「片源」页里点开，房间里换片走不了这类'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    debugPrint('[YQK-SRC] hdmoli sniff page=$page');
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => SniffPage(
        initialUrl: page,
        extraHeaders: HdmoliSource.playHeaders,
      ),
    ));
  }

  /// TVBox 源点开一条结果：详情 → 选线路/剧集 → 直链进播放页（proxy:// 留 P1b）
  Future<void> _playTvbox(SearchHit hit) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final MacCmsItem? base = hit.item;
    if (base == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('这条结果没有作品信息'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final Source? src = _sourceOf(hit);
    final String api = src?.apiUrl ?? '';
    final String ext = src?.ext ?? '';
    if (api.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('这个源没有 api（csp_xxx）'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    messenger.showSnackBar(const SnackBar(
      content: Text('正在读详情…'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));

    MacCmsItem item = base;
    if (item.lines.isEmpty) {
      try {
        final String text =
            await TvboxBridge.detail(api: api, ext: ext, id: base.id);
        final Map<String, dynamic> map = TvboxBridge.decode(text);
        final Object? err = map['error'];
        if (err != null) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(
            content: Text('取详情失败：$err'),
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        final Object? list = map['list'];
        if (list is! List || list.isEmpty || list.first is! Map) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(const SnackBar(
            content: Text('这个源没有返回详情'),
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        final Map<dynamic, dynamic> vod = list.first as Map<dynamic, dynamic>;
        final String from = (vod['vod_play_from'] ?? '').toString();
        final String urls = (vod['vod_play_url'] ?? '').toString();
        final List<MacCmsLine> lines = MacCmsParser.parseLines(from, urls);
        item = MacCmsItem(
          id: base.id,
          name: (vod['vod_name'] ?? base.name).toString(),
          pic: (vod['vod_pic'] ?? base.pic).toString(),
          remarks: (vod['vod_remarks'] ?? base.remarks).toString(),
          lines: lines,
        );
        debugPrint('[YQK-TVBOX] detail api=$api id=${base.id} lines=${lines.length}'
            ' eps=${lines.fold<int>(0, (int a, MacCmsLine l) => a + l.episodes.length)}');
      } on AppException catch (e) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(e.display),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (item.lines.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('详情里没有线路（vod_play_url 为空）'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    MacCmsEpisode? picked;
    if (item.lines.length == 1 && item.lines.first.episodes.length == 1) {
      picked = item.lines.first.episodes.first;
    } else {
      picked = await _pickEpisode(item);
    }
    if (picked == null || !mounted) return;

    final String url = picked.url;
    debugPrint('[YQK-TVBOX] pick api=$api flag=${item.lines.first.name} url=${url.length > 60 ? url.substring(0, 60) : url}');
    if (url.startsWith('proxy://')) {
      messenger.showSnackBar(const SnackBar(
        content: Text('该源需要代理转发，下一轮支持'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!url.startsWith('http')) {
      messenger.showSnackBar(SnackBar(
        content: Text('这条线路不是直链（${url.split(':').first}）'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (widget.pickMode) {
      messenger.showSnackBar(const SnackBar(
        content: Text('TVBox 源要在「片源」页里点开，房间里换片走不了这类'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    messenger.showSnackBar(const SnackBar(
      content: Text('正在解析播放地址…'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
    await _openRaw(hit, url, messenger);
  }

  Source? _sourceOf(SearchHit hit) {
    for (final Source s in _sources) {
      if (s.id == hit.sourceId) return s;
    }
    return null;
  }

  bool _isTvboxHit(SearchHit hit) {
    final Source? s = _sourceOf(hit);
    return s != null && SourceKind.parse(s.kind) == SourceKind.tvbox;
  }

  /// 线路 + 剧集选择面板（网页型片源专用）
  Future<MacCmsEpisode?> _pickEpisode(MacCmsItem item) {
    return showModalBottomSheet<MacCmsEpisode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final ThemeData t = Theme.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    item.name,
                    style: t.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final MacCmsLine line in item.lines)
                        for (int i = 0; i < line.episodes.length; i++)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.play_circle_outline, size: 20),
                            title: Text(line.episodes[i].name),
                            subtitle: Text('${line.name} · 第 ${i + 1} 集'),
                            onTap: () => Navigator.of(ctx).pop(line.episodes[i]),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 这条结果是不是来自网页型片源（决定走嗅探页还是走 resolver）
  bool _isHtmlHit(SearchHit hit) {
    for (final Source s in _sources) {
      if (s.id == hit.sourceId) {
        return SourceKind.parse(s.kind) == SourceKind.html;
      }
    }
    return false;
  }

  /// b 站直链是不是 DASH 分片（`.m4s`，upos 的 upgcxcode 路径）
  static bool _isBiliDash(String u) {
    final String low = u.toLowerCase();
    return low.contains('.m4s') || low.contains('bilivideo.com/upgcxcode/');
  }

  /// MacCMS 一条线路的剧集 → 片单（地址直接用采集站给的直链）
  List<PlayerMedia> _buildPlaylist(
    SearchHit hit,
    String firstUrl,
    ResolvedUrl resolved,
  ) {
    final MacCmsItem? item = hit.item;
    if (item == null) {
      return <PlayerMedia>[
        PlayerMedia(
          id: 'src_${hit.sourceId}_0',
          title: hit.title,
          url: resolved.url,
          headers: resolved.headers,
        ),
      ];
    }
    final MacCmsLine? line = item.firstPlayableLine;
    if (line == null) return <PlayerMedia>[];
    final List<PlayerMedia> out = <PlayerMedia>[];
    for (int i = 0; i < line.episodes.length; i++) {
      final MacCmsEpisode ep = line.episodes[i];
      final String url = i == 0 ? resolved.url : ep.url;
      if (!url.startsWith('http')) continue;
      out.add(
        PlayerMedia(
          id: 'src_${hit.sourceId}_$i',
          title: '${hit.title} · ${ep.name}',
          url: url,
          sourceKind: 'maccms',
          sourceId: item.id,
          headers: i == 0 ? resolved.headers : const <String, String>{},
          episodeIndex: i,
        ),
      );
    }
    if (out.isEmpty) {
      return <PlayerMedia>[
        PlayerMedia(
          id: 'src_${hit.sourceId}_0',
          title: hit.title,
          url: firstUrl,
          headers: resolved.headers,
        ),
      ];
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // P3 调试入口：长按标题弹探针菜单（不进启动路径）
        title: GestureDetector(
          onLongPress: _showProbeMenu,
          child: const Text('片源'),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '网页嗅探',
            onPressed: () => context.push<Object?>(Routes.sniff),
            icon: const Icon(Icons.public),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loadSources,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '导入配置',
            onPressed: () async {
              await context.push<Object?>(Routes.sourceImport);
              await _loadSources();
            },
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: '添加源',
            onPressed: () async {
              await context.push<Object?>(Routes.sourceAdd);
              await _loadSources();
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: LayoutBuilder(
        // 记录本机宽度落在哪个断点档位（C-V2 取证用；结果区另有自己的列数计算）
        builder: (BuildContext ctx, BoxConstraints cons) {
          logScreenClass('sources-page', cons.maxWidth);
          // 统计条：数字实时算，不写死
          final int tvTotal = _sources
              .where((Source s) => SourceKind.parse(s.kind) == SourceKind.tvbox)
              .length;
          final int tvUsable = _sources.where((Source s) {
            if (SourceKind.parse(s.kind) != SourceKind.tvbox) return false;
            final String api = s.apiUrl ?? '';
            return api.startsWith('csp_');
          }).length;
          return RefreshIndicator(
            onRefresh: _loadSources,
            child: ListView(
          padding: const EdgeInsets.all(AppSpace.page),
          children: <Widget>[
            _searchBar(),
            const SizedBox(height: AppSpace.lg),
            _sectionTitle(
              '我的源',
              trailing: tvTotal == 0
                  ? '${_sources.length} 个'
                  : '${_sources.length} 个 · TVBox 可用 $tvUsable/$tvTotal',
            ),
            const SizedBox(height: AppSpace.sm),
            _sourceBlock(),
            const SizedBox(height: AppSpace.lg),
            _sectionTitle(
              '搜索结果',
              trailing: _lastQuery.isEmpty ? '' : '「$_lastQuery」',
            ),
            const SizedBox(height: AppSpace.sm),
            _resultBlock(),
          ],
            ),
          );
        },
      ),
    );
  }

  Widget _searchBar() {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _keyword,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
              hintText: '搜片名，比如「庆余年」',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _searchingAll ? null : _search,
            child: _searchingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('搜索'),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, {String trailing = ''}) {
    return Row(
      children: <Widget>[
        Text(title, style: AppText.section),
        const Spacer(),
        if (trailing.isNotEmpty)
          Text(trailing, style: AppText.sub.copyWith(color: AppColors.textDim)),
      ],
    );
  }

  Widget _sourceBlock() {
    if (_loadingSources) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_sources.isEmpty) {
      return _emptyCard(
        icon: Icons.cloud_off_outlined,
        title: '还没有片源',
        body: '右上角加一个采集站或 B 站，搜索才有东西可看',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _groupedSourceBlocks(),
    );
  }

  /// 按 kind 分组，顺序固定：tvbox → maccms → html → bilibili → direct → 其他。
  ///
  /// 不按数量排序（否则每次刷新位置会跳）。组内按名字排序，空组不显示。
  /// TVBox 组末尾额外列出配置里 js / py 两类「看得见但用不了」的源：
  /// 它们没被导入（没有 JS/Python 引擎），这里只按真名目置灰展示，不发请求。
  List<Widget> _groupedSourceBlocks() {
    const List<SourceKind> order = <SourceKind>[
      SourceKind.tvbox,
      SourceKind.maccms,
      SourceKind.html,
      SourceKind.bilibili,
      SourceKind.direct,
      SourceKind.webdav,
      SourceKind.emby,
      SourceKind.alist,
    ];
    final Map<SourceKind, List<Source>> groups = <SourceKind, List<Source>>{};
    for (final Source s in _sources) {
      groups.putIfAbsent(SourceKind.parse(s.kind), () => <Source>[]).add(s);
    }
    final List<Widget> out = <Widget>[];
    for (final SourceKind k in order) {
      final List<Source> group = groups[k] ?? const <Source>[];
      if (group.isEmpty) continue;
      final List<Source> sorted = List<Source>.of(group)
        ..sort((Source a, Source b) => a.name.compareTo(b.name));
      out.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: 4),
        child: _sectionTitle(k.label, trailing: '${sorted.length} 个'),
      ));
      out.addAll(sorted.map(_sourceTile));
      if (k == SourceKind.tvbox && _tvboxUnavailable.isNotEmpty) {
        out.addAll(_tvboxUnavailable.map(_tvboxUnavailableTile));
      }
    }
    return out;
  }

  /// TVBox 源的类型小标（csp / js / py / maccms），从 apiUrl 反推
  String _tvboxType(Source s) {
    final String api = s.apiUrl ?? '';
    if (api.startsWith('csp_')) return 'csp';
    if (api.contains('drpy')) return 'js';
    if (api.startsWith('./py/')) return 'py';
    if (SourceKind.parse(s.kind) == SourceKind.maccms) return 'maccms';
    return 'other';
  }

  /// js / py 两类不用导入也列出来（中间信息区变淡 + 说明），
  /// 右侧 Switching 与说明按钮仍可点：点了只弹提示，不发任何请求。
  Widget _tvboxUnavailableTile(TvboxSite site) {
    final bool isJs = site.kind == 'js';
    final String why = isJs ? '需 JS 引擎，暂不可用' : '需 Python，暂不可用';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.stroke),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // 未入库的源没有可持久化的开关；点整行只说明原因（不写库、不发请求）
        onTap: () => _showUnavailable(site.name, why),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Opacity(
                opacity: 0.45,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(site.name, style: AppText.card),
                    const SizedBox(height: 2),
                    Text(why,
                        style: AppText.sub.copyWith(color: AppColors.textDim)),
                  ],
                ),
              ),
            ),
            Text(site.kind,
                style: AppText.sub.copyWith(color: AppColors.textDim)),
            const SizedBox(width: AppSpace.sm),
            // 徽章代替假开关：这里根本没有可切换的状态
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Text('未接入',
                  style: AppText.sub.copyWith(color: AppColors.textDim)),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnavailable(String name, String why) {
    debugPrint('[YQK-TVBOX] tap unavailable name=$name reason=$why');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name：$why')),
    );
  }

  /// 「仍要重试」：清掉 unreachable 标记，恢复自动刷新（原 App 也只能手动恢复）
  Future<void> _retryBlocked(Source s) async {
    await _service.dao.setUnreachableByKind(s.kind, false);
    await _loadSources();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${s.name} 已恢复自动刷新，再点一次解析试试')),
    );
  }

  /// 行内副标题用的短标签：采集站的官方长名「采集站（MacCMS）」放行标题里，
  /// 行内只留 MacCMS（长标签会把这一行挤到溢出）。
  String _kindLabel(Source s) {
    final SourceKind k = SourceKind.parse(s.kind);
    return k == SourceKind.maccms ? 'MacCMS' : k.label;
  }

  /// 行内追加的类型小标（TVBox 组才有：csp / js / py）。
  ///
  /// 不放到行右侧做独立控件 —— 右侧已被开关 + 两个图标占满，再挤一列会让
  /// 五星那一行 RenderFlex 溢出（实测 17px）。并进副标题不影响布局。
  String _typeSuffix(Source s) {
    if (!s.id.startsWith('tvbox_')) return '';
    final SourceKind k = SourceKind.parse(s.kind);
    // maccms 组的标签本身就是 MacCMS，重复写一遍没有信息量。
    if (k == SourceKind.maccms) return '';
    return ' · ${_tvboxType(s)}';
  }

  Widget _sourceTile(Source s) {    final Color dot = switch (s.health) {
      'ok' => AppColors.success,
      'slow' => AppColors.warn,
      'down' => AppColors.danger,
      _ => AppColors.textDim,
    };
    final String latency = s.lastLatencyMs == null ? '' : '${s.lastLatencyMs}ms';
    final String healthText = switch (s.health) {
      'ok' => '正常 $latency',
      'slow' => '偏慢 $latency',
      'down' => '连不上',
      _ => '还没检查',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.stroke),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(s.name, style: AppText.card),
                const SizedBox(height: 2),
                Text(
                  s.unreachable == 1
                      ? '${_kindLabel(s)}${_typeSuffix(s)} · 已标记不可恢复，停止自动刷新'
                      : '${_kindLabel(s)}${_typeSuffix(s)} · $healthText',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.sub.copyWith(
                    color: s.unreachable == 1
                        ? AppColors.danger
                        : AppColors.textSub,
                  ),
                ),
                // 网页型源的提示（只加文案，不影响可用性判断与排序）
                if (SourceKind.parse(s.kind) == SourceKind.html) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    '网页型源，部分站点自身播放器异常，可能无法播放',
                    style: AppText.sub.copyWith(color: AppColors.textDim),
                  ),
                ],
                // F9 评分：点星星立刻存（1..5）
                Row(
                  children: <Widget>[
                    for (int i = 1; i <= 5; i++)
                      InkResponse(
                        radius: 14,
                        onTap: () => _rate(s, i),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2, top: 2),
                          child: Icon(
                            (_scores[s.id] ?? 0) >= i
                                ? Icons.star
                                : Icons.star_border,
                            size: 16,
                            color: (_scores[s.id] ?? 0) >= i
                                ? AppColors.warn
                                : AppColors.textDim,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (s.unreachable == 1)
            TextButton(
              onPressed: () => _retryBlocked(s),
              child: const Text('仍要重试'),
            ),
          Switch(
            value: s.enabled == 1,
            onChanged: (bool v) => _toggle(s, v),
          ),
          IconButton(
            tooltip: '检查连接',
            onPressed: _searching.contains(s.id) ? null : () => _check(s),
            icon: _searching.contains(s.id)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _delete(s),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _resultBlock() {
    if (_searchingAll) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _emptyCard(
        icon: Icons.error_outline,
        title: '没搜成',
        body: _error!,
        danger: true,
      );
    }
    if (_hits.isEmpty) {
      return _emptyCard(
        icon: Icons.movie_filter_outlined,
        title: '还没搜索',
        body: '输入片名点搜索，会把所有开启的源一起查一遍',
      );
    }
    final List<SearchHit> ok =
        _hits.where((SearchHit h) => !h.failed).toList();
    final List<SearchHit> bad =
        _hits.where((SearchHit h) => h.failed).toList();
    // G4：手机 2 列 / 中屏 3 列 / 大屏 4 列（断点见 core/layout/breakpoints.dart）。
    // 日志打在整个结果区外面，这样「没搜到」时也能看到本机算出来的断点档位。
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        final ScreenClass sc = logScreenClass('sources', cons.maxWidth);
        final int cols = gridColumns(sc);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (ok.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ok.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: AppSpace.sm,
                  mainAxisSpacing: AppSpace.sm,
                ),
                itemBuilder: (BuildContext context, int i) => _hitCard(ok[i]),
              ),
            for (final SearchHit h in bad)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.block, size: 16, color: AppColors.danger),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(
                        '${h.sourceName}：${h.error}',
                        style: AppText.sub.copyWith(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _hitCard(SearchHit hit) => SearchHitCard(
        hit: hit,
        score: _scores[hit.sourceId],
        onTap: () => _play(hit),
      );
  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String body,
    bool danger = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon,
              size: 36,
              color: danger ? AppColors.danger : AppColors.textDim),
          const SizedBox(height: AppSpace.sm),
          Text(title, style: AppText.card),
          const SizedBox(height: AppSpace.xxs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.sub.copyWith(
              color: danger ? AppColors.danger : AppColors.textSub,
            ),
          ),
        ],
      ),
    );
  }
}