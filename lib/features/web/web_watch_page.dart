import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../platform/room/room_client.dart';

/// 内置验收页：地址栏输入它就走 assets/web/video_test.html（长页面 + 一个 video）
/// 注意：这里走本机 http（/local/webasset）而不是 file://，因为 file:// 文档去拉
/// https 的 <video> 会被 WebView 拦成 net::ERR_FAILED（实测）。
const String kLocalUrl = 'yqk://local';
const String kLocalHttp = 'http://127.0.0.1:8080/local/webasset';

/// D22 第一轮：房间里一起看网页（只做 open / scroll / close）。
///
/// 三条边界：
/// - 只有房主发（scroll / open / close），客人一律只收 —— 否则两端会互相抢滚动位置；
/// - 帧只走 `web` + 现有 seq 通道（服务端 SEQ_FRAMES 已含），不另开一路；
/// - 注入的脚本只有一个 scroll 监听，不改页面、不碰 video / seek / 点击。
class WebWatchPage extends StatefulWidget {
  const WebWatchPage({
    super.key,
    required this.roomClient,
    required this.isHost,
    this.initialUrl,
  });

  final RoomClient roomClient;
  final bool isHost;
  final String? initialUrl;

  @override
  State<WebWatchPage> createState() => _WebWatchPageState();
}

class _WebWatchPageState extends State<WebWatchPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  InAppWebViewController? _web;
  StreamSubscription<Map<String, dynamic>>? _sub;
  String? _url;
  bool _loading = false;

  /// 关闭只发一次（返回键 / 返回箭头 / PopScope 三处都会调 _closeAll）
  bool _closing = false;

  /// 房主滚动节流：scroll 事件每秒几十条，全发会把 relay 打满。
  DateTime _lastTx = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _txGapMs = 120;

  bool get _isHost => widget.isHost;

  @override
  void initState() {
    super.initState();
    final String? ini = widget.initialUrl;
    if (ini != null && ini.isNotEmpty) {
      _url = ini;
      _urlCtrl.text = ini;
    }
    _sub = widget.roomClient.webEvents.listen(_onWeb);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onWeb(Map<String, dynamic> w) {
    final String action = (w['action'] ?? '').toString();
    if (!mounted) return;
    if (action == 'open') {
      final String u = (w['url'] ?? '').toString();
      if (u.isEmpty) return;
      // 客人收到房主的 open：自己也要落到同一页（房主本地已经 loadUrl 过）
      if (!_isHost) {
        debugPrint('[YQK-WEB] open url=$u by-host=false（跟随）');
        setState(() {
          _url = u;
          _urlCtrl.text = u;
        });
        unawaited(_web?.loadUrl(urlRequest: URLRequest(url: WebUri(u))));
      }
      return;
    }
    if (action == 'scroll') {
      if (_isHost) return; // 房主只发不收（服务端也不回显 web）
      final double y = (w['y'] as num?)?.toDouble() ?? 0;
      debugPrint('[YQK-WEB] scroll rx y=${y.toStringAsFixed(1)}');
      unawaited(_web?.evaluateJavascript(
          source: 'window.scrollTo(0, ${y.toStringAsFixed(1)});'));
      return;
    }
    if (action == 'video') {
      if (_isHost) return; // 房主只发不收，和 scroll 同一条规矩
      final String v = (w['v'] ?? '').toString();
      final double t = (w['t'] as num?)?.toDouble() ?? 0;
      debugPrint('[YQK-WEB] video rx v=$v t=${t.toStringAsFixed(2)}');
      unawaited(_web?.evaluateJavascript(
          source: '__yqkVideo("$v", ${t.toStringAsFixed(3)});'));
      return;
    }
    if (action == 'close') {
      debugPrint('[YQK-WEB] close by=${w['by'] ?? w['from']}');
      if (!mounted) return;
      Navigator.maybeOf(context)?.maybePop();
    }
  }

  void _openUrl() {
    final String raw = _urlCtrl.text.trim();
    if (raw.isEmpty) return;
    // yqk://local = 工程内置的验收页（assets/web/video_test.html），不依赖公网
    final String full = (raw == kLocalUrl || raw.startsWith('http'))
        ? raw
        : 'https://$raw';
    debugPrint('[YQK-WEB] open url=$full by-host=$_isHost');
    setState(() {
      _url = full;
      _loading = true;
    });
    // 房主是唯一发出 open 的一端；客人不发（它本来也没有地址栏）
    if (_isHost) {
      widget.roomClient.sendWeb(<String, dynamic>{'action': 'open', 'url': full});
    }
  }

  /// 房主把页面的 play/pause/seek/tick 发出去。客人不发（单向）。
  Future<void> _onVideo(String action, double t) async {
    if (!_isHost) return;
    debugPrint('[YQK-WEB] video tx v=$action t=${t.toStringAsFixed(2)}');
    widget.roomClient.sendWeb(<String, dynamic>{
      'action': 'video',
      'v': action,
      't': t,
    });
  }

  Future<void> _onScroll(double y) async {
    if (!_isHost) return; // 客人滚自己的，不发
    final DateTime now = DateTime.now();
    if (now.difference(_lastTx).inMilliseconds < _txGapMs) return;
    _lastTx = now;
    debugPrint('[YQK-WEB] scroll tx y=${y.toStringAsFixed(1)}');
    widget.roomClient.sendWeb(<String, dynamic>{'action': 'scroll', 'y': y});
  }

  /// 房主广播一次 close。返回键 / 返回箭头都会走到这里，只发一次。
  void _broadcastClose() {
    if (_closing) return;
    _closing = true;
    if (!_isHost) return;
    debugPrint('[YQK-WEB] close by=${widget.roomClient.memberId}');
    widget.roomClient.sendWeb(<String, dynamic>{
      'action': 'close',
      'by': widget.roomClient.memberId,
    });
  }

  void _closeAll() {
    _broadcastClose();
    Navigator.maybeOf(context)?.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final String? url = _url;
    return PopScope(
      // canPop 必须给 true：给 false 的话 Navigator.pop 会被拦下，
      // 客人收到 close 想自己退出去也退不掉（本轮实测就是这么卡的）。
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) return;
        _broadcastClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('一起看网页'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _closeAll,
          ),
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      readOnly: !_isHost,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'https://example.com',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _openUrl(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isHost)
                    FilledButton(onPressed: _openUrl, child: const Text('打开')),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: url == null
                  ? const Center(child: Text('输入网址开始'))
                  : InAppWebView(
                      key: ValueKey<String>(url),
                      // yqk://local 走本机 http 发的验收页；其余走正常 URL
                      initialUrlRequest: URLRequest(
                          url: WebUri(url == kLocalUrl ? kLocalHttp : url)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        // yqk://local 是 file:// 文档，默认不允许它去拉 https 子资源，
                        // 直接导致 <video src="https://…"> 报 net::ERR_FAILED。
                        allowFileAccessFromFileURLs: true,
                        allowUniversalAccessFromFileURLs: true,
                      ),
                      onWebViewCreated: (InAppWebViewController c) {
                        _web = c;
                        c.addJavaScriptHandler(
                          handlerName: 'yqkScroll',
                          callback: (List<dynamic> args) {
                            final double y =
                                (args.isNotEmpty ? (args.first as num?)?.toDouble() : 0) ?? 0;
                            unawaited(_onScroll(y));
                            return null;
                          },
                        );
                        // D22：video 事件（play / pause / seek / tick）
                        c.addJavaScriptHandler(
                          handlerName: 'yqkVideo',
                          callback: (List<dynamic> args) {
                            final String a =
                                (args.isNotEmpty ? args[0]?.toString() : '') ?? '';
                            final double t = (args.length > 1
                                    ? (args[1] as num?)?.toDouble()
                                    : null) ??
                                0;
                            unawaited(_onVideo(a, t));
                            return null;
                          },
                        );
                      },
                      onLoadStop: (InAppWebViewController c, WebUri? u) async {
                        if (mounted) setState(() => _loading = false);
                        final Object? y = await c.evaluateJavascript(
                            source: 'window.scrollY || window.pageYOffset || 0');
                        final Object? dbg = await c.evaluateJavascript(
                            source: "(document.body ? (document.body.innerText||'').length : -1) + '|' + (document.querySelector('video') ? 'v' : 'novideo')");
                        debugPrint('[YQK-WEB] load url=${u?.toString()} y=$y dbg=$dbg');
                        // 滚动监听（第 26 轮验收过，原样保留）
                        await c.evaluateJavascript(source: '''
                          window.addEventListener('scroll', function(){
                            window.flutter_inappwebview.callHandler('yqkScroll', window.scrollY);
                          }, {passive:true});
                        ''');
                        // D22：视频桥。只读 video 的四个事件 + 每秒 tick（暂停时不发）。
                        // 不碰页面其它部分；iframe 里的 video 拿不到（跨源），本轮不支持。
                        await c.evaluateJavascript(source: r'''
                          window.__yqkBridge = function(a, t){
                            window.flutter_inappwebview.callHandler('yqkVideo', a, t);
                          };
                          window.__yqkVideo = function(a, t){
                            var v = document.querySelector('video');
                            if (!v) return;
                            if (a === 'play') { v.currentTime = t; var p = v.play(); if (p && p.catch) p.catch(function(){}); }
                            else if (a === 'pause') { v.pause(); v.currentTime = t; }
                            else if (a === 'seek')  { v.currentTime = t; }
                            else if (a === 'tick')  {
                              var d = Math.abs(v.currentTime - t);
                              if (d > 0.5) {
                                console.log('yqk drift ' + d.toFixed(2) + ' -> ' + t.toFixed(2));
                                v.currentTime = t;
                              }
                            }
                          };
                          (function(){
                            var v = document.querySelector('video');
                            if (!v) { console.log('yqk: no video'); return; }
                            v.addEventListener('play',   function(){ __yqkBridge('play', v.currentTime); });
                            v.addEventListener('pause',  function(){ __yqkBridge('pause', v.currentTime); });
                            v.addEventListener('seeked', function(){ __yqkBridge('seek', v.currentTime); });
                            setInterval(function(){ if (!v.paused) __yqkBridge('tick', v.currentTime); }, 1000);
                          })();
                        ''');
                      },
                      onReceivedError: (InAppWebViewController c, WebResourceRequest r,
                          WebResourceError e) {
                        if (mounted) setState(() => _loading = false);
                        debugPrint('[YQK-WEB] error url=${r.url} ${e.description}');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
