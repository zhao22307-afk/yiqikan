import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/failure_text.dart';
import '../../core/logger.dart';
import '../../platform/tvbox/tvbox_bridge.dart';
import '../db/app_database.dart';
import '../parsers/bilibili.dart';
import 'hdmoli.dart';
import 'maccms.dart';

/// 源类型（sources.kind 的取值，03 §3.4）
enum SourceKind {
  maccms,
  bilibili,
  direct,
  webdav,
  emby,
  alist,

  /// 只有网页没有接口的站点（HDmoli 这一类）：拿 base url，自己解析 HTML
  html,

  /// TVBox 源（dianshi.json 里的 type=3 csp_xxx / type=1 采集站），实际解析靠内置 Java 侧
  tvbox;

  String get prefValue => name;

  String get label {
    switch (this) {
      case SourceKind.maccms:
        return '采集站（MacCMS）';
      case SourceKind.bilibili:
        return 'B 站';
      case SourceKind.direct:
        return '直链';
      case SourceKind.webdav:
        return 'WebDAV';
      case SourceKind.emby:
        return 'Emby';
      case SourceKind.alist:
        return 'AList';
      case SourceKind.html:
        return '网页型（HTML）';
      case SourceKind.tvbox:
        return 'TVBox';
    }
  }

  /// 这个类型要不要填 API 地址（有些只要根地址）
  bool get needsApiUrl =>
      this == SourceKind.maccms || this == SourceKind.tvbox;

  static SourceKind parse(String raw) {
    for (final SourceKind k in SourceKind.values) {
      if (k.name == raw) return k;
    }
    return SourceKind.maccms;
  }
}

/// 健康检查结果
class SourceHealth {
  const SourceHealth({
    required this.health,
    required this.latencyMs,
    this.message,
  });

  /// ok / slow / down / unknown
  final String health;
  final int latencyMs;
  final String? message;

  bool get isDown => health == 'down';
}

/// 聚合搜索的一条结果
class SearchHit {
  const SearchHit({
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.score,
    this.poster = '',
    this.remarks = '',
    this.item,
    this.url,
    this.error,
  });

  final String sourceId;
  final String sourceName;
  final String title;

  /// 与关键词的相似度（0–1），排序用
  final double score;
  final String poster;
  final String remarks;

  /// MacCMS 的原始条目（点进播放要用它的线路/剧集）
  final MacCmsItem? item;

  /// 直链源的地址
  final String? url;

  /// 这个源本身失败时的原因（不阻塞其它源）
  final String? error;

  bool get failed => error != null;
}

/// 片源管理 + 健康检查 + 聚合搜索
class SourceService {
  SourceService({
    required this.dao,
    Dio? dio,
    MacCmsParser? maccms,
    BilibiliClient? bilibili,
    HdmoliSource? hdmoli,
  })  :
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              validateStatus: (int? s) => s != null && s < 500,
            )),
        _maccms = maccms ?? MacCmsParser(),
        _bilibili = bilibili ?? BilibiliClient(),
        _hdmoli = hdmoli ?? HdmoliSource();

  final SourceDao dao;
  final Dio _dio;
  final MacCmsParser _maccms;
  final BilibiliClient _bilibili;
  final HdmoliSource _hdmoli;

  /// 聚合搜索的整体上限（任务要求 20 秒）
  static const Duration searchTimeout = Duration(seconds: 20);

  Future<List<Source>> list({bool enabledOnly = false}) =>
      dao.all(enabledOnly: enabledOnly);

  /// 内置源：第一次打开「片源」页时补一条 HDmoli。幂等，按 baseUrl 判重。
  Future<void> seedBuiltins() async {
    const String base = 'https://www.hdmoli.me';
    try {
      final List<Source> all = await dao.all(enabledOnly: false);
      final bool exists = all.any((Source s) =>
          (s.baseUrl ?? '').replaceAll(RegExp(r'/+$'), '') == base ||
          (s.apiUrl ?? '').replaceAll(RegExp(r'/+$'), '') == base ||
          s.name == 'HDmoli');
      if (exists) {
        debugPrint('[YQK-SRC] seed skip hdmoli（已存在）');
        return;
      }
      final Source s = await add(
        name: 'HDmoli',
        kind: SourceKind.html,
        url: base,
      );
      debugPrint('[YQK-SRC] seed add hdmoli id=${s.id} url=$base');
    } on Object catch (e) {
      debugPrint('[YQK-SRC] seed fail hdmoli $e');
    }
  }

  /// 新增：URL 做基本校验，坏的直接抛 [InvalidSourceException]
  Future<Source> add({
    required String name,
    required SourceKind kind,
    required String url,
  }) async {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const InvalidSourceException('名字不能空着');
    }
    final String normalized = normalizeUrl(url, kind: kind);
    final Source s = Source(
      id: 's_${DateTime.now().millisecondsSinceEpoch}_${trimmedName.hashCode.abs()}',
      name: trimmedName,
      kind: kind.name,
      apiUrl: kind == SourceKind.maccms ? normalized : null,
      baseUrl: kind == SourceKind.maccms ? null : normalized,
      enabled: 1,
      priority: 0,
      health: 'unknown',
      unreachable: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await dao.upsert(s);
    AppLog.add('[YQK-SOURCE] 新增 $kind $trimmedName -> $normalized');
    return s;
  }

  Future<void> update(Source s, {String? name, String? url, bool? enabled}) async {
    Source next = s;
    if (name != null && name.trim().isNotEmpty) {
      next = next.copyWith(name: name.trim());
    }
    if (url != null) {
      final String normalized = normalizeUrl(url, kind: SourceKind.parse(s.kind));
      final bool isMac = SourceKind.parse(s.kind) == SourceKind.maccms;
      next = next.copyWith(
        apiUrl: Value<String?>(isMac ? normalized : next.apiUrl),
        baseUrl: Value<String?>(isMac ? next.baseUrl : normalized),
      );
    }
    if (enabled != null) {
      next = next.copyWith(enabled: enabled ? 1 : 0);
    }
    await dao.upsert(next);
  }

  Future<void> remove(String id) => dao.deleteById(id);

  /// 地址校验：只允许 http/https，采集站必须能看出是 api 入口
  static String normalizeUrl(String raw, {required SourceKind kind}) {
    final String s = raw.trim();
    if (s.isEmpty) throw const InvalidSourceException('地址不能空着');
    final Uri? uri = Uri.tryParse(s);
    if (uri == null || !uri.hasScheme) {
      throw const InvalidSourceException('要以 http:// 或 https:// 开头');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw InvalidSourceException('只支持 http/https，不支持 ${uri.scheme}');
    }
    if (uri.host.isEmpty) throw const InvalidSourceException('缺少域名');
    if (kind == SourceKind.maccms) {
      final String path = uri.path.toLowerCase();
      final bool looksApi = path.contains('api.php') ||
          path.endsWith('/api') ||
          path.contains('provide/vod') ||
          path.contains('/api/');
      if (!looksApi) {
        throw const InvalidSourceException(
          '采集站一般要填到 api.php/provide/vod 这一层',
        );
      }
    }
    String out = uri.toString();
    if (!out.endsWith('/') && !uri.path.contains('.')) out = '$out/';
    return out;
  }

  /// 只探一次，不写库（P04「测试连接」用，源还没保存）
  Future<SourceHealth> probe({
    required SourceKind kind,
    required String url,
  }) async {
    final int started = DateTime.now().millisecondsSinceEpoch;
    String health = 'down';
    String? message;
    try {
      switch (kind) {
        case SourceKind.maccms:
          final List<MacCmsItem> list =
              await _maccms.search(url, 'test').timeout(kHttpReadTimeout);
          health = list.isEmpty ? 'slow' : 'ok';
          message = list.isEmpty ? '能连上但搜不到东西' : null;
        case SourceKind.bilibili:
          final bool ok = await _bilibili.ensureKeys();
          health = ok ? 'ok' : 'slow';
          if (!ok) message = '拿不到 WBI 密钥';
        case SourceKind.direct:
        case SourceKind.webdav:
        case SourceKind.emby:
        case SourceKind.alist:
        case SourceKind.html:
          final Response<dynamic> resp =
              await _dio.get<dynamic>(url).timeout(kHttpReadTimeout);
          final int code = resp.statusCode ?? 0;
          health = code < 400 ? 'ok' : 'slow';
          if (code >= 400) message = '返回 $code';
        case SourceKind.tvbox:
          // TVBox 源的健康检查要跑 Java 侧，本轮不探（P 系列后续接）
          health = 'unknown';
          message = '未接入检查';
      }
    } on AppException catch (e) {
      health = 'down';
      message = e.userMessage;
    } on Object catch (e) {
      health = 'down';
      message = '连不上（${e.runtimeType}）';
    }
    final int latency = DateTime.now().millisecondsSinceEpoch - started;
    if (health == 'ok' && latency > 3000) health = 'slow';
    return SourceHealth(health: health, latencyMs: latency, message: message);
  }

  /// 健康检查：请求一次首页或搜索，记录 health / latency / last_check_at
  Future<SourceHealth> check(Source s) async {
    final int started = DateTime.now().millisecondsSinceEpoch;
    final SourceKind kind = SourceKind.parse(s.kind);
    String health = 'down';
    String? message;
    try {
      switch (kind) {
        case SourceKind.maccms:
          final String api = s.apiUrl ?? s.baseUrl ?? '';
          final List<MacCmsItem> list = await _maccms
              .search(api, 'test')
              .timeout(kHttpReadTimeout);
          health = list.isEmpty ? 'slow' : 'ok';
          message = list.isEmpty ? '能连上但搜不到东西' : null;
        case SourceKind.bilibili:
          final bool ok = await _bilibili.ensureKeys();
          health = ok ? 'ok' : 'slow';
          if (!ok) message = '拿不到 WBI 密钥';
        case SourceKind.direct:
        case SourceKind.webdav:
        case SourceKind.emby:
        case SourceKind.alist:
        case SourceKind.html:
          final Response<dynamic> resp = await _dio
              .get<dynamic>(s.baseUrl ?? s.apiUrl ?? '')
              .timeout(kHttpReadTimeout);
          final int code = resp.statusCode ?? 0;
          health = code < 400 ? 'ok' : 'slow';
          if (code >= 400) message = '返回 $code';
        case SourceKind.tvbox:
          // TVBox 源的健康检查要跑 Java 侧，本轮不探（P 系列后续接）
          health = 'unknown';
          message = '未接入检查';
      }
    } on AppException catch (e) {
      health = 'down';
      message = e.userMessage;
    } on Object catch (e) {
      health = 'down';
      message = '连不上（${e.runtimeType}）';
    }
    final int latency = DateTime.now().millisecondsSinceEpoch - started;
    // 超过 3 秒算慢
    if (health == 'ok' && latency > 3000) health = 'slow';
    await dao.updateHealth(s.id, health, latency);
    AppLog.add('[YQK-SOURCE] 健康检查 ${s.name} -> $health ${latency}ms${message == null ? '' : '（$message）'}');
    return SourceHealth(health: health, latencyMs: latency, message: message);
  }

  /// 聚合搜索：并发查所有 enabled 源，单源失败只标错不阻塞
  Future<List<SearchHit>> search(String keyword) async {
    final String kw = keyword.trim();
    if (kw.isEmpty) return <SearchHit>[];
    final List<Source> sources = await dao.all(enabledOnly: true);
    // 第33轮排查用：只报告这次搜索「选了哪些源」，不改任何筛选逻辑。
    debugPrint('[YQK-SRC] search q=$kw sources=${sources.length} '
        'ids=${sources.map((Source s) => s.id).join(',')}');
    if (sources.isEmpty) return <SearchHit>[];

    final List<Future<List<SearchHit>>> jobs = sources
        .map((Source s) => _searchOne(s, kw).timeout(
              searchTimeout,
              onTimeout: () => <SearchHit>[
                SearchHit(
                  sourceId: s.id,
                  sourceName: s.name,
                  title: '',
                  score: 0,
                  error: FailureText.offline.message,
                ),
              ],
            ))
        .toList();

    final List<List<SearchHit>> each = await Future.wait(jobs);
    final List<SearchHit> all = <SearchHit>[];
    for (final List<SearchHit> part in each) {
      all.addAll(part);
    }
    // 失败条目永远排最后
    all.sort((SearchHit a, SearchHit b) {
      if (a.failed != b.failed) return a.failed ? 1 : -1;
      return b.score.compareTo(a.score);
    });
    final String summary = '[YQK-SEARCH] "$kw" 命中 ${all.where((SearchHit h) => !h.failed).length} 条，'
        '失败 ${all.where((SearchHit h) => h.failed).length} 个源';
    AppLog.add(summary);
    // 第34轮验收用：AppLog 只进环形缓冲、不进 logcat，这条是同一内容的落盘副本。
    debugPrint(summary);
    return all;
  }

  Future<List<SearchHit>> _searchOne(Source s, String kw) async {
    final SourceKind kind = SourceKind.parse(s.kind);
    try {
      switch (kind) {
        case SourceKind.maccms:
          final List<MacCmsItem> items =
              await _maccms.search(s.apiUrl ?? s.baseUrl ?? '', kw);
          return items
              .map((MacCmsItem item) => SearchHit(
                    sourceId: s.id,
                    sourceName: s.name,
                    title: item.name,
                    score: titleScore(kw, item.name),
                    poster: item.pic,
                    remarks: item.remarks,
                    item: item,
                  ))
              .toList();
        case SourceKind.bilibili:
          final List<BilibiliSearchItem> items =
              await _bilibili.searchVideos(kw);
          return items
              .map((BilibiliSearchItem item) => SearchHit(
                    sourceId: s.id,
                    sourceName: s.name,
                    title: item.title,
                    score: titleScore(kw, item.title),
                    poster: item.pic,
                    remarks: 'B 站 · ${item.durationText}',
                    url: 'https://www.bilibili.com/video/${item.bvid}',
                  ))
              .toList();
        case SourceKind.direct:
          // 直链源没有"搜索"，只有用户自己粘的地址
          return <SearchHit>[];
        case SourceKind.html:
          final List<MacCmsItem> items = await _hdmoli.search(kw);
          return items
              .map((MacCmsItem item) => SearchHit(
                    sourceId: s.id,
                    sourceName: s.name,
                    title: item.name,
                    score: titleScore(kw, item.name),
                    poster: item.pic,
                    remarks: item.remarks,
                    item: item,
                  ))
              .toList();
        case SourceKind.webdav:
        case SourceKind.emby:
        case SourceKind.alist:
          throw UnsupportedException('${kind.label} 的搜索');
        case SourceKind.tvbox:
          // csp_xxx 源：类加载与调用在 Java 侧（TvboxBatch.searchOne）
          return _searchTvbox(s, kw);
      }
    } on AppException catch (e) {
      return <SearchHit>[
        SearchHit(
          sourceId: s.id,
          sourceName: s.name,
          title: '',
          score: 0,
          error: FailureText.lineOf(e),
        ),
      ];
    } on Object catch (e) {
      return <SearchHit>[
        SearchHit(
          sourceId: s.id,
          sourceName: s.name,
          title: '',
          score: 0,
          error: FailureText.lineOf(e),
        ),
      ];
    }
  }

  /// TVBox 源（csp_xxx）的搜索：交给 Java 侧的 TvboxBatch.searchOne。
  ///
  /// 返回 `{"error": ...}` 时不抛异常，产出一条带 error 的 SearchHit —— 113 个源里
  /// 有多少挂掉要能照样列出来，不能让一个源把整轮搜索炸掉。
  Future<List<SearchHit>> _searchTvbox(Source s, String kw) async {
    final String api = s.apiUrl ?? '';
    if (api.isEmpty) {
      return <SearchHit>[
        SearchHit(
            sourceId: s.id,
            sourceName: s.name,
            title: '',
            score: 0,
            error: '这个源没有 api（csp_xxx）'),
      ];
    }
    final String text;
    try {
      text = await TvboxBridge.search(api: api, ext: s.ext ?? '', kw: kw);
    } on AppException catch (e) {
      return <SearchHit>[
        SearchHit(
            sourceId: s.id,
            sourceName: s.name,
            title: '',
            score: 0,
            error: e.display),
      ];
    }
    final Map<String, dynamic> map = TvboxBridge.decode(text);
    return parseTvboxHits(s, kw, map);
  }

  /// 把 Java 侧返回的 JSON（已 decode）映射成 SearchHit 列表。
  ///
  /// 纯函数，便于单测：`{"list":[]}` → 空表；`{"error":...}` → 一条带 error 的命中。
  static List<SearchHit> parseTvboxHits(
      Source s, String kw, Map<String, dynamic> map) {
    final Object? err = map['error'];
    if (err != null) {
      return <SearchHit>[
        SearchHit(
            sourceId: s.id,
            sourceName: s.name,
            title: '',
            score: 0,
            error: err.toString()),
      ];
    }
    final Object? list = map['list'];
    if (list is! List || list.isEmpty) return <SearchHit>[];
    final List<SearchHit> hits = <SearchHit>[];
    for (final Object? e in list) {
      if (e is! Map) continue;
      final String name = (e['vod_name'] ?? '').toString();
      final String id = (e['vod_id'] ?? '').toString();
      if (name.isEmpty || id.isEmpty) continue;
      hits.add(SearchHit(
        sourceId: s.id,
        sourceName: s.name,
        title: name,
        score: titleScore(kw, name),
        poster: (e['vod_pic'] ?? '').toString(),
        remarks: (e['vod_remarks'] ?? '').toString(),
        // 搜索不返线路，lines 留空，点进去时再拉详情
        item: MacCmsItem(
          id: id,
          name: name,
          pic: (e['vod_pic'] ?? '').toString(),
          remarks: (e['vod_remarks'] ?? '').toString(),
        ),
      ));
    }
    return hits;
  }

  static double titleScore(String keyword, String title) {
    final String k = keyword.trim().toLowerCase();
    final String t = title.trim().toLowerCase();
    if (k.isEmpty || t.isEmpty) return 0;
    if (k == t) return 1;
    if (t == k) return 1;
    if (t.contains(k)) return 0.9;
    if (k.contains(t)) return 0.8;
    int prefix = 0;
    while (prefix < k.length &&
        prefix < t.length &&
        k.codeUnitAt(prefix) == t.codeUnitAt(prefix)) {
      prefix++;
    }
    final double ratio = prefix / (k.length > t.length ? k.length : t.length);
    return 0.2 + ratio * 0.5;
  }

  /// B 站搜索项 → 便于 JSON 调试
  static String describeHits(List<SearchHit> hits) => jsonEncode(hits
      .map((SearchHit h) => <String, Object?>{
            'source': h.sourceName,
            'title': h.title,
            'score': h.score.toStringAsFixed(2),
            'error': h.error,
          })
      .toList());
}
