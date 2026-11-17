import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/player_controller.dart';
import '../../platform/sniffer/sniff_result.dart';
import '../../platform/sniffer/sniff_rules.dart';
import '../../routing/routes.dart';
import '../../theme/app_theme.dart';

/// P09/C03 网页嗅探页（M5 第 1–8 条）。
///
/// 六层嗅探里本页负责「跑起来、看得见、点得进」：
/// - L1 运行时钩子：UserScript 注入 [SniffRules.sniffInjectScript]，
///   `forMainFrameOnly: false` 让 iframe 也吃到（= L5 递归）；
/// - L2 资源时序 / L3 静态 DOM 都在同一份脚本里；
/// - 结果统一进 Dart 侧 [SniffRules.rank]（视频在前、字幕在后、各 8 条）。
///
/// 页面本身不写死任何站点地址：用户输什么就看什么。
class SniffPage extends StatefulWidget {
  const SniffPage({super.key, this.initialUrl, this.extraHeaders});

  /// 从别处带过来的网址（例如分享文案里提出来的链接）
  final String? initialUrl;

  /// 片源适配器指定的请求头（例如 HDmoli 要求 Referer 指回自己的首页）。
  /// 合并时以这里为准，盖掉默认的 Referer/UA。
  final Map<String, String>? extraHeaders;

  @override
  State<SniffPage> createState() => _SniffPageState();
}

class _SniffPageState extends State<SniffPage> {
  final TextEditingController _urlText = TextEditingController();
  final Map<String, SniffResult> _hits = <String, SniffResult>{};

  InAppWebViewController? _web;
  bool _loading = false;
  bool _started = false;
  bool _mseSeen = false;

  /// 页面像登录页 / 命中里带 login 字样 → 空态日志归到 need-login（M5 待修 ②）
  bool _needLoginSeen = false;
  String _pageTitle = '';
  String _currentUrl = '';
  int _rankVersion = 0;

  /// 播放时带的默认 UA（不要写具体站点，只写播放器自己的身份）
  static const String _defaultUa =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    final String? seed = widget.initialUrl;
    if (seed != null && seed.isNotEmpty) {
      _urlText.text = seed;
      // 带网址进来就别让用户再点一次「打开」
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        unawaited(_go(seed));
      });
    }
  }

  @override
  void dispose() {
    _urlText.dispose();
    super.dispose();
  }

  Future<void> _go(String raw) async {
    String url = raw.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    setState(() {
      _started = true;
      _loading = true;
      _hits.clear();
      _mseSeen = false;
    _needLoginSeen = false;
      _pageTitle = '';
      _currentUrl = url;
    });
    debugPrint('[YQK-SNIFF] go url=$url');
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Map<String, String> _headersFor(String url) {
    // 绝大多数站点只认 Referer；页面地址就是最靠谱的 Referer
    final Map<String, String> base = <String, String>{
      'Referer': _currentUrl.isEmpty ? url : _currentUrl,
      'User-Agent': _defaultUa,
    };
    final Map<String, String>? extra = widget.extraHeaders;
    if (extra == null || extra.isEmpty) return base;
    // 片源适配器说了算：它给的请求头盖掉默认值
    base.addAll(extra);
    return base;
  }

  void _onSniffPayload(Object? payload) {
    final String raw = payload?.toString() ?? '';
    if (raw.isEmpty) return;
    Map<String, Object?>? data;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) data = decoded;
    } on FormatException {
      return;
    }
    if (data == null) return;

    final String url = (data['url'] ?? '').toString();
    final String via = (data['via'] ?? '').toString();
    final String page = (data['page'] ?? _currentUrl).toString();
    if (url.isEmpty) return;

    final SniffResult? hit = SniffRules.fromVia(
      url,
      via: via,
      pageUrl: page,
      headers: _headersFor(page),
    );
    if (hit == null) return;

    final String lower = hit.url.toLowerCase();
    if (lower.contains('login') || lower.contains('passport')) {
      _needLoginSeen = true;
    }
    final String key = SniffRules.normalize(hit.url);
    if (_hits.containsKey(key)) return;

    debugPrint('[YQK-SNIFF] hit via=$via layer=${hit.source} '
        'kind=${hit.kind.name} url=${_short(hit.url)}');
    setState(() {
      if (hit.kind == SniffKind.mse) {
        _mseSeen = true;
      } else {
        _hits[key] = hit;
      }
      _rankVersion++;
    });
    _dumpRank();
  }

  /// 验收第 2 条要「8 条结果排序实际输出」，所以每次变化都把榜单打一遍
  void _dumpRank() {
    final List<SniffResult> ranked = SniffRules.rank(_hits.values);
    final int videos =
        ranked.where((SniffResult r) => r.kind == SniffKind.video).length;
    final int subs = ranked.length - videos;
    debugPrint('[YQK-SNIFF] rank v=$_rankVersion total=${ranked.length} '
        'video=$videos subtitle=$subs mse=$_mseSeen');
    for (int i = 0; i < ranked.length; i++) {
      final SniffResult r = ranked[i];
      debugPrint('[YQK-SNIFF] #${i + 1} ${r.kind.name} '
          'layer=${r.source} url=${_short(r.url)}');
    }
  }

  static String _short(String url) =>
      url.length <= 110 ? url : '${url.substring(0, 110)}…';

  void _play(SniffResult hit) {
    final Map<String, String> headers = hit.headers.isEmpty
        ? _headersFor(hit.pageUrl.isEmpty ? hit.url : hit.pageUrl)
        : hit.headers;
    debugPrint('[YQK-SNIFF] play kind=${hit.kind.name} layer=${hit.source} '
        'headers=${headers.keys.join(",")} url=${_short(hit.url)}');
    context.push(
      Routes.player,
      extra: PlayerMedia(
        id: hit.url,
        title: _pageTitle.isEmpty ? hit.url : _pageTitle,
        url: hit.url,
        sourceKind: 'sniff',
        headers: headers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网页嗅探'),
        actions: <Widget>[
          IconButton(
            tooltip: '重新嗅探',
            icon: const Icon(Icons.refresh),
            onPressed: () => _go(_currentUrl),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.sm,
              AppSpace.md,
              AppSpace.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _urlText,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (String v) => _go(v),
                    decoration: const InputDecoration(
                      hintText: '粘贴网页地址，比如某个播放页',
                      prefixIcon: Icon(Icons.public),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                FilledButton(
                  onPressed: () => _go(_urlText.text),
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            flex: 5,
            child: _started
                ? InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_currentUrl),
                    ),
                    initialUserScripts: UnmodifiableListView<UserScript>(
                      <UserScript>[
                        UserScript(
                          source: SniffRules.sniffInjectScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                          forMainFrameOnly: false,
                        ),
                      ],
                    ),
                    onWebViewCreated:
                        (InAppWebViewController controller) {
                      _web = controller;
                      controller.addJavaScriptHandler(
                        handlerName: 'sniff',
                        callback: (List<dynamic> args) {
                          _onSniffPayload(args.isEmpty ? null : args.first);
                          return null;
                        },
                      );
                    },
                    onLoadStart: (InAppWebViewController c, WebUri? uri) {
                      setState(() => _loading = true);
                    },
                    onLoadStop: (InAppWebViewController c, WebUri? uri) async {
                      final String title = (await c.getTitle()) ?? '';
                      if (!mounted) return;
                      setState(() {
                        _loading = false;
                        _pageTitle = title;
                      });
                      // 单页应用可能在 load 之后才挂播放器，再注一次
                      await c.evaluateJavascript(
                        source: SniffRules.sniffInjectScript,
                      );
                    },
                    onReceivedError: (InAppWebViewController c,
                        WebResourceRequest req, WebResourceError err) {
                      if (req.isForMainFrame == true) {
                        debugPrint('[YQK-SNIFF] 页面加载失败：${err.description}');
                        setState(() => _loading = false);
                      }
                    },
                  )
                : const _SniffHint(
                    icon: Icons.travel_explore,
                    title: '输入网址开始嗅探',
                    lines: <String>[
                      '只在这台手机上打开你给的页面，不经过任何中转服务',
                      '页面里的视频和字幕地址会被抓出来，点一下就播',
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 4,
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final List<SniffResult> ranked = SniffRules.rank(_hits.values);
    if (!_started) {
      return const SizedBox.shrink();
    }
    if (ranked.isEmpty) {
      // 日志要能区分「为什么没结果」，UI 四句照旧一起给（用户不需要看分类）
      final String reason = _mseSeen
          ? 'mse'
          : (_loading ? 'loading' : (_needLoginSeen ? 'need-login' : 'no-media'));
      debugPrint('[YQK-SNIFF] empty reason=$reason url=${_currentUrl.split('?').first} hits=${_hits.length}');
      if (_mseSeen) {
        return const _SniffHint(
          icon: Icons.layers_clear,
          title: '这个页面用 MSE 播放，地址取不出来',
          lines: <String>[
            '播放器把视频切片喂给自己，页面上没有可直接用的地址',
            '换一个直链页面，或用「片源」里的采集站',
          ],
        );
      }
      if (_loading) {
        return const _SniffHint(
          icon: Icons.hourglass_bottom,
          title: '页面还在加载，边加载边看',
          lines: <String>[
            '点一下页面里的播放按钮，地址才会出来',
          ],
        );
      }
      return const _SniffHint(
        icon: Icons.search_off,
        title: '这个页面里没找到能播的地址',
        lines: <String>[
          '先点页面里的播放按钮，再回来看',
          '有些站点要登录才给地址，这种情况换一个源',
          '也可能是页面用了 MSE（分片喂给播放器），那就没直链可取',
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      itemCount: ranked.length,
      separatorBuilder: (BuildContext ctx, int i) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) {
        final SniffResult r = ranked[i];
        final bool isVideo = r.kind == SniffKind.video;
        return ListTile(
          dense: true,
          leading: Icon(
            isVideo ? Icons.play_circle_outline : Icons.subtitles_outlined,
            color: isVideo ? AppColors.primary : AppColors.textSub,
          ),
          title: Text(
            r.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.card,
          ),
          subtitle: Text(
            '${r.kind.label} · 第 ${r.source.replaceFirst('l', 'L')} 层',
            style: AppText.sub,
          ),
          trailing: isVideo
              ? Icon(Icons.chevron_right, color: AppColors.textDim)
              : null,
          onTap: isVideo ? () => _play(r) : null,
        );
      },
    );
  }
}

class _SniffHint extends StatelessWidget {
  const _SniffHint({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 40, color: AppColors.textDim),
          const SizedBox(height: AppSpace.sm),
          Text(title, style: AppText.section, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.xs),
          for (final String line in lines)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Text(
                line,
                style: AppText.sub,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}