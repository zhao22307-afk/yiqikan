import 'sniff_result.dart';

/// 嗅探六层的纯逻辑部分（04 §8）：分类、编码还原、去重排序、注入脚本。
///
/// 这一层不碰网络、不碰 WebView，方便单测；WebView 那边只负责把
/// [sniffInjectScript] 注进去，再把 callHandler('sniff') 的 JSON 丢进
/// [SniffRules.fromVia] / [SniffRules.rank]。
class SniffRules {
  SniffRules._();

  /// 每类最多留几条（04 §8.3：多了用户看不过来）
  static const int maxPerKind = 8;

  /// JS 侧回传的「哪条钩子抓到的」，不直接当层号用
  static const String viaXhr = 'xhr';
  static const String viaFetch = 'fetch';
  static const String viaDom = 'dom';
  static const String viaPerf = 'perf';
  static const String viaProxy = 'proxy';
  static const String viaHtml = 'html';
  static const String viaIframe = 'iframe';
  static const String viaMse = 'mse';

  static const Set<String> _videoExts = <String>{
    'm3u8',
    'mp4',
    'flv',
    'mkv',
    'ts',
    'mov',
    'webm',
  };

  static const Set<String> _subtitleExts = <String>{
    'ass',
    'ssa',
    'srt',
    'vtt',
    'sub',
  };

  /// JS 的 via → 六层编号。
  ///
  /// 之前把 via 当层号写进 source，导致 _layerRank 全部落到 default 9，
  /// 排序退化成插入顺序；这里统一在 Dart 侧映射（04 §8.1 的 L1/L2/L3/L5）。
  static String sourceOfVia(String via) {
    switch (via) {
      case viaXhr:
      case viaFetch:
      case viaDom:
      case viaProxy:
        return 'l1'; // 运行时钩子
      case viaPerf:
        return 'l2'; // 资源时序
      case viaHtml:
        return 'l3'; // 静态 HTML 扫描
      case viaIframe:
        return 'l5'; // iframe 递归
      case viaMse:
        return 'l1';
      default:
        return 'l9'; // 认不出来：排最后，不冒充任何一层
    }
  }

  /// 04 §8.4 编码还原：内联 JSON 里的反斜杠转义要先还原再判定
  static String normalize(String raw) {
    String s = raw.trim();
    if (s.isEmpty) return s;
    s = s
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u002f', '/')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\x26', '&')
        .replaceAll('&amp;', '&');
    s = s.replaceAll('&#39;', "'").replaceAll('&quot;', '"');
    return s;
  }

  /// 取小写扩展名（带 query 也能认），拿不到返回空串
  static String extensionOf(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String path = uri?.path ?? url;
    final int slash = path.lastIndexOf('/');
    final String name = slash >= 0 ? path.substring(slash + 1) : path;
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static bool isVideoUrl(String url) {
    final String ext = extensionOf(url);
    if (_videoExts.contains(ext)) return true;
    final String low = url.toLowerCase();
    return low.contains('/live/') ||
        low.contains('/hls/') ||
        low.contains('.m3u8?') ||
        low.contains('.mp4?') ||
        low.contains('.flv?');
  }

  static bool isSubtitleUrl(String url) {
    final String ext = extensionOf(url);
    if (_subtitleExts.contains(ext)) return true;
    final String low = url.toLowerCase();
    return low.contains('.ass?') ||
        low.contains('.srt?') ||
        low.contains('.vtt?');
  }

  /// 视频优先级：m3u8 > mp4 > flv > 其它（04 §8.3）
  static int videoPriority(String url) {
    final String ext = extensionOf(url);
    if (ext == 'm3u8' || url.toLowerCase().contains('.m3u8')) return 0;
    if (ext == 'mp4' || url.toLowerCase().contains('.mp4')) return 1;
    if (ext == 'flv' || url.toLowerCase().contains('.flv')) return 2;
    return 3;
  }

  /// 字幕优先级：ass > srt > vtt > 其它
  static int subtitlePriority(String url) {
    final String ext = extensionOf(url);
    if (ext == 'ass' || ext == 'ssa') return 0;
    if (ext == 'srt') return 1;
    if (ext == 'vtt') return 2;
    return 3;
  }

  /// 一条命中的候选地址 → SniffResult（认不出来返回 null，不硬塞）
  static SniffResult? fromUrl(
    String rawUrl, {
    required String source,
    String pageUrl = '',
    Map<String, String> headers = const <String, String>{},
  }) {
    final String url = normalize(rawUrl);
    if (url.isEmpty) return null;
    final String low = url.toLowerCase();
    if (low.startsWith('blob:') || low.startsWith('data:')) return null;
    final SniffKind kind;
    if (isSubtitleUrl(url)) {
      kind = SniffKind.subtitle;
    } else if (isVideoUrl(url)) {
      kind = SniffKind.video;
    } else {
      return null;
    }
    return SniffResult(
      url: url,
      kind: kind,
      source: source,
      pageUrl: pageUrl,
      headers: headers,
    );
  }

  /// 注入脚本回调 → SniffResult。
  ///
  /// via 是 JS 说的钩子名；MSE 是第 4 种情况（不是「没找到」），单独成条，
  /// 由 UI 显示「页面用 MSE，无法直取」。
  static SniffResult? fromVia(
    String rawUrl, {
    required String via,
    String pageUrl = '',
    Map<String, String> headers = const <String, String>{},
  }) {
    final String source = sourceOfVia(via);
    if (via == viaMse) {
      return SniffResult(
        url: normalize(rawUrl),
        kind: SniffKind.mse,
        source: source,
        pageUrl: pageUrl,
        headers: headers,
      );
    }
    return fromUrl(rawUrl, source: source, pageUrl: pageUrl, headers: headers);
  }

  /// 去重 + 分类型排序 + 每类截断到 8 条。
  ///
  /// 视频全部排在字幕前面；MSE 提示不参与排序（单独展示）。
  static List<SniffResult> rank(Iterable<SniffResult> raw) {
    final Map<String, SniffResult> seen = <String, SniffResult>{};
    for (final SniffResult r in raw) {
      if (r.kind == SniffKind.mse) continue;
      final String key = normalize(r.url);
      if (key.isEmpty) continue;
      seen.putIfAbsent(key, () => r);
    }

    final List<SniffResult> videos = seen.values
        .where((SniffResult r) => r.kind == SniffKind.video)
        .toList()
      ..sort((SniffResult a, SniffResult b) {
        final int p = videoPriority(a.url).compareTo(videoPriority(b.url));
        if (p != 0) return p;
        return _layerRank(a).compareTo(_layerRank(b));
      });

    final List<SniffResult> subtitles = seen.values
        .where((SniffResult r) => r.kind == SniffKind.subtitle)
        .toList()
      ..sort((SniffResult a, SniffResult b) {
        final int p =
            subtitlePriority(a.url).compareTo(subtitlePriority(b.url));
        if (p != 0) return p;
        return _layerRank(a).compareTo(_layerRank(b));
      });

    return <SniffResult>[
      ...videos.take(maxPerKind),
      ...subtitles.take(maxPerKind),
    ];
  }

  static int _layerRank(SniffResult r) {
    switch (r.source.toLowerCase()) {
      case 'l0':
        return 0;
      case 'l1':
        return 1;
      case 'l2':
        return 2;
      case 'l3':
        return 3;
      case 'l4':
        return 4;
      case 'l5':
        return 5;
      default:
        return 9;
    }
  }

  /// 04 §8.2 的 L1 注入脚本（按本轮要求补了三处）：
  /// 1) HTMLMediaElement.src 的 setter —— MutationObserver 抓不到 srcObject
  ///    和「设了又立刻改」的情况；
  /// 2) MSE 检测 —— video.src 是 blob: 且页面有 MediaSource 时发一条 mse 标记；
  /// 3) Performance 兜底从一次改成 3s / 8s / 15s 三次。
  static const String sniffInjectScript = r'''
(function(){
  if (window.__yqkSniffed) return;
  window.__yqkSniffed = true;

  const send = (url, via) => {
    if (!url) return;
    let abs;
    try { abs = new URL(url, location.href).href; } catch (e) { return; }
    // 在 iframe 里就别再报原来的 via 了——层号要能区分「子框架里抓到的」
    var inFrame = false;
    try { inFrame = window.top !== window.self; } catch (e) { inFrame = true; }
    try {
      window.flutter_inappwebview.callHandler('sniff', JSON.stringify({
        url: abs, via: inFrame ? 'iframe' : via, page: location.href
      }));
    } catch (e) {}
  };

  const emit = (url, via) => {
    if (!url) return;
    if (url.startsWith('data:')) return;
    if (url.startsWith('blob:')) {
      // MSE：blob 地址取不到真实媒体，单独报一条，别混进「没找到」
      if (window.MediaSource) send(url, 'mse');
      return;
    }
    send(url, via);
  };

  const XO = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, u){
    emit(u, 'xhr');
    return XO.apply(this, arguments);
  };

  const F = window.fetch;
  if (F) {
    window.fetch = function(i){
      const u = typeof i === 'string' ? i : (i && i.url);
      emit(u, 'fetch');
      return F.apply(this, arguments);
    };
  }

  // HTMLMediaElement.src 的 setter（srcObject / 立即改写都抓得到）
  const hookSrc = (proto, label) => {
    try {
      const d = Object.getOwnPropertyDescriptor(proto, 'src');
      if (d && d.set) {
        Object.defineProperty(proto, 'src', {
          configurable: true,
          enumerable: d.enumerable,
          get: d.get,
          set: function(v){ emit(v, label); return d.set.call(this, v); }
        });
      }
    } catch (e) {}
  };
  hookSrc(HTMLMediaElement.prototype, 'dom');
  if (window.HTMLTrackElement) hookSrc(HTMLTrackElement.prototype, 'dom');
  if (window.HTMLSourceElement) hookSrc(HTMLSourceElement.prototype, 'dom');

  const scanDom = () => {
    document.querySelectorAll('video,audio,source,track').forEach(el => {
      const raw = el.getAttribute ? el.getAttribute('src') : null;
      emit(raw || el.src || el.currentSrc, 'dom');
      if (el.srcObject) send(el.currentSrc || 'blob:mse', 'mse');
    });
  };
  scanDom();
  try {
    new MutationObserver(scanDom).observe(document.documentElement, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['src']
    });
  } catch (e) {}

  // 页面可能 5 秒后才加载视频：3s / 8s / 15s 各扫一次
  [3000, 8000, 15000].forEach(t => {
    setTimeout(() => {
      try {
        performance.getEntriesByType('resource').forEach(r => emit(r.name, 'perf'));
      } catch (e) {}
      scanDom();
    }, t);
  });
})();
''';
}
