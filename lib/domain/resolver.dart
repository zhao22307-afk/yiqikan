import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/errors/app_exception.dart';
import '../core/logger.dart';
import '../data/parsers/bilibili.dart';

/// 一条可选音轨（DASH 音视频分离时用，04 §9.1）
class ResolvedTrack {
  const ResolvedTrack({
    required this.url,
    required this.label,
    this.headers = const <String, String>{},
    this.bandwidth = 0,
  });

  final String url;
  final String label;
  final Map<String, String> headers;
  final int bandwidth;
}

/// 解析结果（04 §9.1，字段名不要改）
class ResolvedUrl {
  const ResolvedUrl({
    required this.url,
    this.headers = const <String, String>{},
    this.expiresAt,
    this.deadline,
    this.lastUrlUpdate,
    this.audioUrl,
    required this.resolver,
    this.needsRelay = false,
    this.audioTracks = const <ResolvedTrack>[],
  });

  final String url;

  /// 播放时必须带上的头（Referer / UA / Cookie）—— M2 已验证 http-header-fields 生效
  final Map<String, String> headers;

  /// 本地判定的过期时刻（B 站直链：now + 90min，见 04 §9）
  final DateTime? expiresAt;

  /// CDN 自己在 URL 里给的 deadline（原样留档，只用于排查，不用于判过期）
  final DateTime? deadline;

  /// 这条 URL 最后一次刷新的时刻（原 App 的 last_url_update）
  final DateTime? lastUrlUpdate;

  /// 分离音轨的地址；`bilibili://` 这类占位直链缺了它就没法播
  final String? audioUrl;

  /// 'direct' | 'bilibili' | 'quark' | 'sniff' ...
  final String resolver;

  /// 目标域名在白名单里（带签名 CDN）→ 需要走 04 §7 的 relay
  final bool needsRelay;

  final List<ResolvedTrack> audioTracks;

  bool get expired {
    final DateTime? e = expiresAt;
    return e != null && DateTime.now().isAfter(e);
  }

  /// 还剩不到 5 分钟就当过期（04 §9 第 0 步）
  bool get aboutToExpire {
    final DateTime? e = expiresAt;
    return e != null &&
        e.difference(DateTime.now()) < Resolver.cacheSafetyMargin;
  }

  /// 四条刷新判据（原 App 的 needsRefresh，任一成立就刷）
  bool get needsRefresh => refreshReason != null;

  /// 返回第一条成立的原因（给人看 + 打日志），没原因返回 null
  String? get refreshReason {
    if (url.trim().isEmpty) return '直链为空';
    if (url.startsWith('bilibili://') && (audioUrl ?? '').isEmpty) {
      return 'bilibili://链接但audioUrl为空';
    }
    final DateTime? e = expiresAt;
    if (e == null) return null;
    final Duration left = e.difference(DateTime.now());
    if (left <= Duration.zero) return '已过期';
    if (left < Resolver.refreshAhead) {
      return 'last_url_update超过 ${Resolver.refreshAhead.inMinutes} 分钟';
    }
    return null;
  }

  /// 验收钩子（B19-d）：只改有效期，别的字段不动
  ResolvedUrl copyWithExpiresAt(DateTime? at) {
    return ResolvedUrl(
      url: url,
      headers: headers,
      expiresAt: at,
      deadline: deadline,
      lastUrlUpdate: lastUrlUpdate,
      audioUrl: audioUrl,
      resolver: resolver,
      needsRelay: needsRelay,
      audioTracks: audioTracks,
    );
  }
}

/// 某一档解析器的统一形态（04 §9 的每一级）
abstract class ResolveStage {
  const ResolveStage();

  /// 日志与错误详情里显示的名字
  String get name;

  /// 返回 null 表示「这一档不认识这个链接，交给下一档」；
  /// 抛 [AppException] 表示「认识但失败了」。
  Future<ResolvedUrl?> tryResolve(String url);
}

/// 1) 已经是直链：HEAD 200 且 Content-Type 是 video/*，或者扩展名够明显
class DirectStage extends ResolveStage {
  DirectStage({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              followRedirects: true,
              validateStatus: (int? s) => s != null && s < 400,
            ));

  final Dio _dio;

  static const Set<String> videoExtensions = <String>{
    '.mp4', '.m4v', '.mkv', '.webm', '.flv', '.ts', '.m3u8', '.mpd', //
    '.mov', '.avi', '.wmv', '.mp3', '.m4a', '.aac', '.flac', '.ogg', '.wav',
  };

  @override
  String get name => '直链';

  @override
  Future<ResolvedUrl?> tryResolve(String url) async {
    final String path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final bool byExtension =
        videoExtensions.any((String ext) => path.endsWith(ext));
    if (!byExtension) {
      // 扩展名不像视频：只对 http(s) 做一次 HEAD 探一下类型
      if (!url.startsWith('http')) return null;
    }
    try {
      final Response<dynamic> head = await _dio.head<dynamic>(url);
      final String type =
          (head.headers.value('content-type') ?? '').toLowerCase();
      if (head.statusCode != null && head.statusCode! >= 400) {
        return null;
      }
      final bool isMedia = type.startsWith('video/') ||
          type.startsWith('audio/') ||
          type.contains('mpegurl') ||
          type.contains('octet-stream') ||
          type.isEmpty;
      if (!byExtension && !isMedia) return null;
      return ResolvedUrl(
        url: url,
        resolver: 'direct',
        needsRelay: Resolver.needsRelayFor(url),
      );
    } on DioException {
      // HEAD 不通也可能只是站点不支持 HEAD：扩展名像就直接放行
      if (byExtension) {
        return ResolvedUrl(
          url: url,
          resolver: 'direct',
          needsRelay: Resolver.needsRelayFor(url),
        );
      }
      return null;
    }
  }
}

/// 2) B 站：BV/av 链接 → view 拿 cid → playurl（WBI 签名）
class BilibiliStage extends ResolveStage {
  BilibiliStage({
    BilibiliClient? client,
    Dio? dio,
    this.isBlocked,
    this.onBlocked,
  })
      : _client = client ?? BilibiliClient(),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              headers: BilibiliClient.defaultHeaders,
              validateStatus: (int? s) => s != null && s < 500,
            ));

  final BilibiliClient _client;
  final Dio _dio;

  /// 读「这个源是否被标记不可恢复」（由上层注入，查 sources.unreachable）
  final Future<bool> Function()? isBlocked;

  /// 命中 -10403/87007/87008 时写标记（由上层注入）
  final Future<void> Function()? onBlocked;

  static final RegExp _bvid = RegExp(r'(BV[0-9A-Za-z]{10})');
  static final RegExp _aid = RegExp(r'/video/av(\d+)');

  /// 番剧：/bangumi/play/ep12345 或 ?ep_id=12345（14 §1.7）
  static final RegExp _epLink = RegExp(r'/bangumi/play/ep(\d+)');
  static final RegExp _epQuery = RegExp(r'[?&]ep_id=(\d+)');

  /// 直播：live.bilibili.com/12345（14 §1.19）
  static final RegExp _liveRoom = RegExp(r'live\.bilibili\.com/(?:h5/)?(\d+)');

  @override
  String get name => 'B 站';

  @override
  Future<ResolvedUrl?> tryResolve(String url) async {
    // 原 App 的行为：当前集一旦被判「不可恢复」，就不再打接口，也不让播放器错误触发刷新
    final bool blocked = await (isBlocked?.call() ?? Future<bool>.value(false));
    if (blocked && _isBilibiliUrl(url)) {
      debugPrint('[YQK-BILI] needsRefresh=false: 当前集已标记为不可恢复解析失败');
      debugPrint('[YQK-BILI] 当前集地区不可观看，停止自动刷新与后端兜底');
      throw const RegionLockedException();
    }
    try {
      return await _resolveBilibili(url);
    } on RegionLockedException {
      await _markBlocked('地区不可观看');
      rethrow;
    } on ContentLockedException {
      await _markBlocked('版权/会员限制');
      rethrow;
    }
  }

  bool _isBilibiliUrl(String url) =>
      url.contains('bilibili.com') || url.startsWith('bilibili://');

  Future<void> _markBlocked(String why) async {
    debugPrint('[YQK-BILI] 命中不可恢复失败（$why），写 unreachable 标记并停自动刷新');
    debugPrint('[YQK-BILI] 当前集地区不可观看，停止自动刷新与后端兜底');
    await onBlocked?.call();
  }

  Future<ResolvedUrl?> _resolveBilibili(String url) async {
    // 直播：一条 m3u8，没有 DASH 音轨（audioTracks 必须是空数组）
    final RegExpMatch? live = _liveRoom.firstMatch(url);
    if (live != null) {
      final int roomId = int.parse(live.group(1)!);
      final BilibiliLiveInfo info = await _client.livePlayUrl(roomId);
      debugPrint('[YQK-BILI-LIVE] room=$roomId title=${info.title} '
          'url=${info.url.substring(0, info.url.length.clamp(0, 80))}');
      return ResolvedUrl(
        url: info.url,
        headers: info.headers,
        expiresAt: DateTime.now().add(Resolver.bilibiliUrlTtl),
        deadline: _deadlineOf(info.url),
        lastUrlUpdate: DateTime.now(),
        resolver: 'bilibili-live',
        needsRelay: true,
      );
    }

    // 番剧：ep 号 → season 拿 cid → pgc playurl（与点播共用同一个解析函数）
    final String? epIdText =
        _epLink.firstMatch(url)?.group(1) ?? _epQuery.firstMatch(url)?.group(1);
    if (epIdText != null) {
      final int epId = int.parse(epIdText);
      final PgcSeason season = await _client.pgcSeason(epId: epId);
      final PgcEpisode ep = season.byEpId(epId) ?? season.episodes.first;
      final BilibiliPlayInfo info =
          await _client.pgcPlayUrl(epId: ep.epId, cid: ep.cid);
      debugPrint('[YQK-BILI-PGC] ep_id=${ep.epId} cid=${ep.cid} '
          'season=${season.seasonId} qn=${info.quality} '
          'dashVideos=${info.videoCount} audios=${info.audios.length} '
          'base=${info.video.url.substring(0, info.video.url.length.clamp(0, 60))}');
      final List<ResolvedTrack> tracks = info.audiosByQuality
          .map((DashStream s) => ResolvedTrack(
                url: s.url,
                label: _audioLabel(s.id),
                headers: info.headers,
                bandwidth: s.bandwidth,
              ))
          .toList();
      return ResolvedUrl(
        url: info.video.url,
        headers: info.headers,
        // 原 App 按 90 分钟判过期，不吃 CDN 的 deadline 原值
        expiresAt: DateTime.now().add(Resolver.bilibiliUrlTtl),
        deadline: _deadlineOf(info.video.url),
        lastUrlUpdate: DateTime.now(),
        audioUrl: tracks.isEmpty ? null : tracks.first.url,
        resolver: 'bilibili-pgc',
        needsRelay: true,
        audioTracks: tracks,
      );
    }

    final String? bvid = _bvid.firstMatch(url)?.group(1);
    final String? aid = _aid.firstMatch(url)?.group(1);
    if (bvid == null && aid == null) return null;

    // 1) 详情拿 cid（14 §1.3：pages[].cid 是播放必填）
    final Map<String, Object?> view = await _view(bvid: bvid, aid: aid);
    final List<Object?>? pages = view['pages'] as List<Object?>?;
    if (pages == null || pages.isEmpty) throw const NotFoundException();
    final Map<String, Object?> first = (pages.first as Map<Object?, Object?>)
        .map<String, Object?>((Object? k, Object? v) => MapEntry<String, Object?>('$k', v));
    final int cid = (first['cid'] as num?)?.toInt() ?? 0;
    final String realBvid = '${view['bvid'] ?? bvid ?? ''}';
    if (cid == 0) throw const ParseException('B 站分 P 信息');

    // 2) playurl（内部自带 qn 降级链）
    final BilibiliPlayInfo info = await _client.playUrl(
      bvid: realBvid,
      cid: cid,
    );

    // 验收用：把 playurl 拿到的关键值打出来（地址只截前 60 字符，不落全量签名）
    final String head = info.video.url;
    debugPrint('[YQK-BILI] bvid=$realBvid cid=$cid qn=${info.quality} '
        'baseUrl=${head.length > 60 ? head.substring(0, 60) : head} '
        'audio=${info.audiosByQuality.isEmpty ? '-' : info.audiosByQuality.first.id} '
        'headerKeys=${info.headers.keys.join(",")} '
        'hasReferer=${info.headers.containsKey("Referer")} '
        'hasUa=${info.headers.containsKey("User-Agent")}');
    final List<ResolvedTrack> tracks = info.audiosByQuality
        .map((DashStream s) => ResolvedTrack(
              url: s.url,
              label: _audioLabel(s.id),
              headers: info.headers,
              bandwidth: s.bandwidth,
            ))
        .toList();

    AppLog.add(
      '[YQK-BILI] bvid=$realBvid cid=$cid qn=${info.quality} '
      'video=${info.video.width}x${info.video.height} '
      'audio=${info.audiosByQuality.map((DashStream s) => s.id).join(",")}',
    );

    return ResolvedUrl(
      url: info.video.url,
      headers: info.headers,
      // 原 App 按 90 分钟判过期；CDN 的 deadline 只留档
      expiresAt: DateTime.now().add(Resolver.bilibiliUrlTtl),
      deadline: _deadlineOf(info.video.url),
      lastUrlUpdate: DateTime.now(),
      audioUrl: tracks.isEmpty ? null : tracks.first.url,
      resolver: 'bilibili',
      needsRelay: true,
      audioTracks: tracks,
    );
  }

  Future<Map<String, Object?>> _view({
    String? bvid,
    String? aid,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'https://api.bilibili.com/x/web-interface/view',
        queryParameters: <String, String>{
          'bvid': ?bvid,
          'aid': ?aid,
        },
      );
      final Object? raw = resp.data;
      final Map<String, Object?>? root = raw is Map<Object?, Object?>
          ? raw.map<String, Object?>(
              (Object? k, Object? v) => MapEntry<String, Object?>('$k', v))
          : null;
      if (root == null) throw const ParseException('B 站视频详情');
      final int code = (root['code'] as num?)?.toInt() ?? 0;
      if (code != 0) {
        if (code == -404) throw const NotFoundException();
        if (code == -10403) throw const RegionLockedException();
        throw AppException('B 站说这条视频看不了（错误码 $code）');
      }
      final Object? data = root['data'];
      if (data is Map<Object?, Object?>) {
        return data.map<String, Object?>(
            (Object? k, Object? v) => MapEntry<String, Object?>('$k', v));
      }
      throw const ParseException('B 站视频详情');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw RequestTimeoutException(cause: e);
      }
      throw NetworkException(cause: e);
    }
  }

  static String _audioLabel(int id) {
    switch (id) {
      case 30216:
        return '64K';
      case 30232:
        return '132K';
      case 30280:
        return '192K';
      case 30250:
        return '杜比全景声';
      case 30251:
        return 'Hi-Res 无损';
      default:
        return '音轨 $id';
    }
  }

  static DateTime? _deadlineOf(String url) {
    final String? deadline = Uri.tryParse(url)?.queryParameters['deadline'];
    if (deadline == null) return null;
    final int? sec = int.tryParse(deadline);
    if (sec == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  }
}

/// 3) 网盘（夸克/115/123/天翼）：本轮只定义接口
class NetdiskStage extends ResolveStage {
  const NetdiskStage();

  @override
  String get name => '网盘';

  @override
  Future<ResolvedUrl?> tryResolve(String url) async {
    if (!_looksLikeNetdisk(url)) return null;
    throw const UnsupportedException('网盘直链解析');
  }

  static bool _looksLikeNetdisk(String url) =>
      url.contains('pan.quark.cn') ||
      url.contains('115.com') ||
      url.contains('123pan.com') ||
      url.contains('cloud.189.cn');
}

/// 4) Emby / WebDAV：本轮只定义接口
class EmbyWebdavStage extends ResolveStage {
  const EmbyWebdavStage();

  @override
  String get name => 'Emby/WebDAV';

  @override
  Future<ResolvedUrl?> tryResolve(String url) async {
    final String u = url.toLowerCase();
    if (!u.contains('/emby/') &&
        !u.contains('/webdav') &&
        !u.contains('/dav')) {
      return null;
    }
    throw const UnsupportedException('Emby / WebDAV 直链解析');
  }
}

/// 5) 嗅探（04 §8 六层）：本轮只定义接口
class SnifferStage extends ResolveStage {
  const SnifferStage();

  @override
  String get name => '嗅探';

  @override
  Future<ResolvedUrl?> tryResolve(String url) async {
    throw const UnsupportedException('网页嗅探（六层）');
  }
}

/// 六级解析链（04 §9）
///
/// 顺序固定：缓存 → 直链 → B 站 → 网盘 → Emby/WebDAV → 嗅探 → 报错分类型。
/// 本轮只实现前两档；后三档明确抛 [UnsupportedException]，不返回 null 也不留空方法。
class Resolver {
  Resolver({
    List<ResolveStage>? stages,
    BilibiliClient? bilibili,
    DirectStage? direct,
    Future<bool> Function()? bilibiliBlocked,
    Future<void> Function()? markBilibiliBlocked,
  }) : _stages = stages ??
            <ResolveStage>[
              direct ?? DirectStage(),
              BilibiliStage(
                client: bilibili,
                isBlocked: bilibiliBlocked,
                onBlocked: markBilibiliBlocked,
              ),
              const NetdiskStage(),
              const EmbyWebdavStage(),
              const SnifferStage(),
            ];

  final List<ResolveStage> _stages;

  /// 04 §9 第 0 步 / 15 §B19：内存 LRU 上限 200 条，key 必须归一化
  static const int cacheLimit = 200;

  /// 剩余不足这个时间就当过期，免得播到一半签名失效
  static const Duration cacheSafetyMargin = Duration(minutes: 5);

  /// 原 App 的刷新提前量：last_url_update 超过 90 分钟就重取
  static const Duration refreshAhead = Duration(minutes: 10);

  /// B 站直链本地判定的有效期（原 App 用 90 分钟，不用 CDN 的 120 分钟）
  static const Duration bilibiliUrlTtl = Duration(minutes: 90);

  final LinkedHashMap<String, ResolvedUrl> _cache =
      LinkedHashMap<String, ResolvedUrl>();

  /// 缓存 key：去空白 → 只保留 scheme/host/path → query 按 key 排序重拼
  static String cacheKey(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null) return url.trim();
    final List<String> keys = uri.queryParametersAll.keys.toList()..sort();
    final List<String> pairs = <String>[];
    for (final String k in keys) {
      for (final String v in uri.queryParametersAll[k] ?? const <String>[]) {
        pairs.add('$k=$v');
      }
    }
    final String query = pairs.join('&');
    // 重建 Uri 而不是 replace：replace(fragment: null) 是「保持原值」，去不掉 #frag
    final Uri cleaned = Uri(
      scheme: uri.scheme.toLowerCase(),
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: query.isEmpty ? null : query,
    );
    return cleaned.toString();
  }

  /// 上游请求计数（B19 验收用）：key 是 stage/接口名
  final Map<String, int> debugUpstream = <String, int>{};

  void _bumpUpstream(String key) {
    debugUpstream[key] = (debugUpstream[key] ?? 0) + 1;
  }

  /// 验收钩子：把所有缓存条目的 expiresAt 拨到过去，模拟过期（B19-d）
  int debugExpireAll() {
    int n = 0;
    for (final MapEntry<String, ResolvedUrl> e in _cache.entries.toList()) {
      _cache[e.key] = e.value.copyWithExpiresAt(
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      n++;
    }
    if (n > 0) {
      debugPrint('[YQK-CACHE] 手动把 $n 条缓存的有效期改到过去');
    }
    return n;
  }

  int get cacheSize => _cache.length;

  void _remember(String key, ResolvedUrl value) {
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > cacheLimit) {
      final String oldest = _cache.keys.first;
      _cache.remove(oldest);
      debugPrint('[YQK-CACHE] 超过 $cacheLimit 条，淘汰最早的一条');
    }
  }

  /// 04 §9.1：带签名 CDN 的域名走 relay
  static const List<String> relayHostSuffixes = <String>[
    'bilivideo.com',
    'bilivideo.cn',
    'hdslb.com',
    'szbdyd.com',
    'akamaized.net',
    'quark.cn',
    '115.com',
  ];

  static bool needsRelayFor(String url) {
    final String host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    return relayHostSuffixes.any((String s) => host.endsWith(s));
  }

  /// 解析入口：失败时抛 [ResolveFailedException]，里面带每一档的原因
  Future<ResolvedUrl> resolve(String url) async {
    final String raw = url.trim();
    // 04 §9 第 0 步：key 必须归一化（query 按 key 排序重拼），否则同一个视频
    // 因为参数顺序不同会重复打上游（15 §B19）
    final String key = cacheKey(raw);
    final ResolvedUrl? hit = _cache[key];
    if (hit != null) {
      final String? reason = hit.refreshReason;
      if (reason == null) {
        debugPrint('[YQK-CACHE] hit key=$key resolver=${hit.resolver} '
            'expiresIn=${hit.expiresAt?.difference(DateTime.now()).inMinutes}min');
        return hit;
      }
      debugPrint('[YQK-CACHE] needsRefresh=true: $reason（key=$key，重新请求）');
    } else {
      debugPrint('[YQK-CACHE] miss key=$key');
    }

    final Map<String, String> failures = <String, String>{};
    for (final ResolveStage stage in _stages) {
      try {
        _bumpUpstream(stage.name);
        final ResolvedUrl? r = await stage.tryResolve(raw);
        if (r == null) {
          failures[stage.name] = '这一档不认识这个链接';
          continue;
        }
        debugPrint('[YQK-RESOLVE] ${stage.name} 命中 resolver=${r.resolver} '
            'relay=${r.needsRelay} tracks=${r.audioTracks.length}');
        _remember(key, r);
        return r;
      } on AppException catch (e) {
        failures[stage.name] = e.display;
        debugPrint('[YQK-RESOLVE] ${stage.name} 原始异常 $e');
        debugPrint('[YQK-RESOLVE] ${stage.name} 失败：${e.userMessage} type=${e.runtimeType} cause=${e.cause}');
      } on Object catch (e) {
        failures[stage.name] = '这一档出了点意外';
        debugPrint('[YQK-RESOLVE] ${stage.name} 异常：$e');
      }
    }
    throw ResolveFailedException(failures);
  }

  /// 清缓存（源配置改了之后调）
  void clearCache() => _cache.clear();

  /// 单条作废：播放器判定直链失效时调（原 App 的 invalidate）
  bool invalidate(String url) {
    final bool removed = _cache.remove(cacheKey(url)) != null;
    debugPrint('[YQK-CACHE] invalidate key=${cacheKey(url)} removed=$removed');
    return removed;
  }
}
