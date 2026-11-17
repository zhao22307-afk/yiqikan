import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 第 39 轮：B 站降级播放页。
///
/// 本地解析拿到的 b 站地址是 DASH 分片（`*.m4s`，只有视频轨、没有 init 段），
/// 本机内核 `prepare` 直接返回 -1，界面弹「这个源连不上」。
/// 这类地址交给 b 站自己的播放器（H5）播：能播、能拖、能切清晰度，
/// 代价是不同步 —— 所以只用于片源页，不进房间（房间换片源仍走 media 帧）。
const String kBiliMobileUa = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// 页内脚本：藏掉顶部导航 / 底部「打开 App」条，并让 <video> 自己播起来。
/// 选择器在 b 站改版后可能拿不到 —— 整段 try 包住，拿不到就算了。
const String _kBiliTidyJs = r'''
try {
  var st = document.createElement('style');
  st.innerHTML = '.m-navbar,.bili-header,.fixed-openapp,.m-openapp,.open-app{display:none!important}';
  (document.head || document.documentElement).appendChild(st);
  var v = document.querySelector('video');
  if (v) {
    v.setAttribute('playsinline', '');
    v.setAttribute('webkit-playsinline', '');
    v.setAttribute('controls', 'controls');
    var p = v.play();
    if (p && p.catch) p.catch(function () {});
  }
} catch (e) {}
''';

class BiliWatchPage extends StatefulWidget {
  const BiliWatchPage({super.key, required this.url, this.title});

  /// b 站页面地址（`https://www.bilibili.com/video/BV…` 或 `…/bangumi/play/…`）
  final String url;
  final String? title;

  @override
  State<BiliWatchPage> createState() => _BiliWatchPageState();
}

class _BiliWatchPageState extends State<BiliWatchPage> {
  bool _loading = true;
  String? _err;

  @override
  Widget build(BuildContext context) {
    final String t = (widget.title == null || widget.title!.isEmpty)
        ? 'B 站'
        : widget.title!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: <Widget>[
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_err != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3CD),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(_err!, style: const TextStyle(fontSize: 12)),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                useShouldOverrideUrlLoading: true,
                userAgent: kBiliMobileUa,
              ),
              shouldOverrideUrlLoading:
                  (InAppWebViewController c, NavigationAction action) async {
                final String scheme =
                    (action.request.url?.scheme ?? '').toLowerCase();
                // 「打开 App」/ 唤端：留在本页，不要把用户甩出 App
                if (scheme == 'bilibili' || scheme == 'bili' ||
                    scheme == 'intent' || scheme == 'biliapp') {
                  debugPrint('[YQK-BILI-WEB] block scheme=$scheme '
                      'url=${action.request.url}');
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStart: (InAppWebViewController c, WebUri? u) {
                if (!mounted) return;
                setState(() {
                  _loading = true;
                  _err = null;
                });
              },
              onLoadStop: (InAppWebViewController c, WebUri? u) async {
                if (mounted) setState(() => _loading = false);
                debugPrint('[YQK-BILI-WEB] load url=${u?.toString()}');
                try {
                  await c.evaluateJavascript(source: _kBiliTidyJs);
                  final Object? probe = await c.evaluateJavascript(
                      source: "(document.querySelector('video') ? 'v' : 'novideo')");
                  debugPrint('[YQK-BILI-WEB] probe=$probe');
                } catch (e) {
                  debugPrint('[YQK-BILI-WEB] js 注入失败 $e');
                }
              },
              onReceivedError: (InAppWebViewController c,
                  WebResourceRequest req, WebResourceError err) {
                // 只报主文档的错；子资源（广告 / 统计）失败不打扰用户
                if (req.isForMainFrame != true) return;
                debugPrint('[YQK-BILI-WEB] 主文档错误 ${err.description}');
                if (!mounted) return;
                setState(() => _loading = false);
                setState(() => _err = '页面打不开：${err.description}（可返回重试或换 Wi-Fi）');
              },
            ),
          ),
        ],
      ),
    );
  }
}
