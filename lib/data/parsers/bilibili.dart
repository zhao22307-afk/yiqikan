import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/entities/subtitle.dart';

/// B 站接口客户端（14 §1）
///
/// 只做三件事：取 WBI 密钥、签名、取 playurl / 字幕。
/// 所有失败都翻成 [AppException] 子类，绝不把 `code=-352` 这种数字丢给界面。
class WbiSignedQuery {
  const WbiSignedQuery(this.value, this.wts);

  /// 已经排好序、带 `w_rid` 的 query 串（不含 `?`）
  final String value;

  /// 参与签名的时间戳（秒）
  final int wts;
}

/// `mixinKeyEncTab`（**完整 64 项**，一个都不能少；只用前 32 项，见 14 §1.2 的坑 5）
const List<int> kMixinKeyEncTab = <int>[
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, //
  33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, //
  26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, //
  20, 34, 44, 52,
];

/// WBI 签名（14 §1.2）
class Wbi {
  Wbi._();

  /// 从 `/x/web-interface/nav` 的两个 png url 里取 key（文件名去掉扩展名）
  static String keyFromUrl(String url) {
    final String name = url.split('/').last;
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 拼 mixinKey：64 项表取前 32 个下标
  static String mixinKey(String imgKey, String subKey) {
    final String raw = '$imgKey$subKey';
    if (raw.length < 64) {
      throw ParseException('B 站 WBI 密钥不足 64 位（拿到 ${raw.length} 位）');
    }
    return kMixinKeyEncTab.take(32).map((int i) => raw[i]).join();
  }

  /// 按 key 升序拼 query 并签名；[wtsSeconds] 只在测试里显式给
  static WbiSignedQuery sign(
    Map<String, String> params,
    String imgKey,
    String subKey, {
    int? wtsSeconds,
  }) {
    final String key = mixinKey(imgKey, subKey);
    final int wts =
        wtsSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);

    // 值里过滤 ! ' ( ) * 五个字符，只影响签名，不影响真的请求参数
    final Map<String, String> cleaned = <String, String>{};
    params.forEach((String k, String v) {
      cleaned[k] = v.replaceAll(RegExp(r"[!'()*]"), '');
    });
    cleaned['wts'] = '$wts';

    final List<String> keys = cleaned.keys.toList()..sort();
    final String query = keys
        .map((String k) => '$k=${Uri.encodeQueryComponent(cleaned[k]!)}')
        .join('&');
    final String wRid =
        md5.convert(utf8.encode('$query$key')).toString();
    return WbiSignedQuery('$query&w_rid=$wRid', wts);
  }
}

/// 一条 DASH 流
class DashStream {
  const DashStream({
    required this.id,
    required this.url,
    required this.bandwidth,
    this.codecs = '',
    this.width = 0,
    this.height = 0,
  });

  final int id;
  final String url;
  final int bandwidth;
  final String codecs;
  final int width;
  final int height;
}

/// playurl 的结果
class BilibiliPlayInfo {
  const BilibiliPlayInfo({
    required this.video,
    required this.audios,
    required this.quality,
    required this.headers,
    required this.videoCount,
  });

  final DashStream video;
  final List<DashStream> audios;
  final int quality;

  /// 播放这些地址必须带上的头（Referer + UA，14 §1.0）
  final Map<String, String> headers;

  /// dash.video 里的条目数（验收 a 要报这个数）
  final int videoCount;

  /// 音轨按码率从高到低
  List<DashStream> get audiosByQuality {
    final List<DashStream> list = List<DashStream>.of(audios)
      ..sort((DashStream a, DashStream b) => b.bandwidth.compareTo(a.bandwidth));
    return list;
  }
}

/// B 站搜索结果一条（14 §1.10）
class BilibiliSearchItem {
  const BilibiliSearchItem({
    required this.bvid,
    required this.title,
    this.pic = '',
    this.durationText = '',
  });

  final String bvid;
  final String title;
  final String pic;
  final String durationText;
}

/// B 站直播（14 §1.19）：只有一条 m3u8 直链，没有 DASH 音轨分离
class BilibiliLiveInfo {
  const BilibiliLiveInfo({
    required this.url,
    required this.roomId,
    required this.title,
    required this.headers,
    this.expiresAt,
  });

  final String url;
  final int roomId;
  final String title;
  final Map<String, String> headers;

  /// 直播地址有时效（几小时），过期要重取（15 §B4）
  final DateTime? expiresAt;
}

/// 番剧一集（14 §1.7：cid 在 episodes[].cid，不在 pages[].cid）
class PgcEpisode {
  const PgcEpisode({
    required this.epId,
    required this.cid,
    required this.bvid,
    required this.title,
    this.longTitle = '',
    this.duration = 0,
    this.badge = '',
  });

  final int epId;
  final int cid;
  final String bvid;
  final String title;
  final String longTitle;
  final int duration;

  /// 角标：正片是空，预告/PV/花絮会带字（用它过滤，别按数组下标对齐）
  final String badge;
}

/// 番剧一季
class PgcSeason {
  const PgcSeason({
    required this.seasonId,
    required this.title,
    required this.cover,
    required this.episodes,
  });

  final int seasonId;
  final String title;
  final String cover;
  final List<PgcEpisode> episodes;

  /// 按 ep_id 建映射（不许用数组下标：episodes 里混着预告/PV，下标会错位）
  Map<int, PgcEpisode> get episodeMap => <int, PgcEpisode>{
        for (final PgcEpisode ep in episodes) ep.epId: ep,
      };

  PgcEpisode? byEpId(int epId) {
    for (final PgcEpisode ep in episodes) {
      if (ep.epId == epId) return ep;
    }
    return null;
  }
}

/// 番剧元数据缓存条目（24 小时）
class _SeasonCacheEntry {
  const _SeasonCacheEntry(this.value, this.at);

  final PgcSeason value;
  final DateTime at;
}

/// B 站客户端
class BilibiliClient {
  BilibiliClient({Dio? dio, DateTime Function()? clock})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              headers: defaultHeaders,
              // 自己去判断 code，不让 Dio 因为 4xx 直接抛
              validateStatus: (int? s) => s != null && s < 500,
            )) {
    _clock = clock ?? DateTime.now;
  }

  /// 14 §1.0：少了这几个头会 412 或被风控
  static const Map<String, String> defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://www.bilibili.com/',
    'Origin': 'https://www.bilibili.com',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
  };

  static const String kNavPath = '/x/web-interface/nav';
  static const String kPlayUrlPath = '/x/player/wbi/playurl';
  static const String kPlayerV2Path = '/x/player/v2';
  static const String kSearchPath = '/x/web-interface/wbi/search/type';
  static const String kPgcSeasonPath = '/pgc/view/web/season';
  static const String kPgcPlayUrlPath = '/pgc/player/web/playurl';
  /// 直播三个接口在 api.live.bilibili.com，不在 api.bilibili.com（实测后者返回 HTML 错误页）
  static const String kLiveBase = 'https://api.live.bilibili.com';
  static const String kLiveRoomInfoPath = '/room/v1/Room/get_info';
  static const String kLivePlayUrlPath = '/room/v1/Room/playUrl';
  static const String kLivePlayInfoPath =
      '/xlive/web-room/v2/index/getRoomPlayInfo';

  /// 把 season 的 episodes[] 转成 PgcEpisode，并过滤预告/PV/花絮。
  /// 对齐一律按 ep_id（下标是错的：episodes 里混着预告，第 2 集会被播成预告）。
  static List<PgcEpisode> parsePgcEpisodes(
    List<Object?> raw, {
    void Function(String reason)? onSkip,
  }) {
    final List<PgcEpisode> eps = <PgcEpisode>[];
    for (final Object? item in raw) {
      final Map<String, Object?>? m = _asMap(item);
      if (m == null) continue;
      final int cid = (m['cid'] as num?)?.toInt() ?? 0;
      if (cid == 0) {
        onSkip?.call('cid=0');
        continue;
      }
      final String badge = (m['badge'] as String?) ?? '';
      final String title = (m['title'] as String?) ?? '';
      final String longTitle = (m['long_title'] as String?) ?? '';
      final String probe = '$badge $title $longTitle';
      final bool teaser = badge.contains('预告') ||
          probe.contains('预告') ||
          probe.contains('PV') ||
          probe.contains('花絮');
      if (teaser) {
        final String reason = 'badge=$badge title=$title long=$longTitle';
        onSkip?.call(reason);
        debugPrint('[YQK-BILI-SEASON] 跳过非正片 ep=${m['id']} $reason');
        continue;
      }
      eps.add(PgcEpisode(
        epId: (m['id'] as num?)?.toInt() ?? 0,
        cid: cid,
        bvid: (m['bvid'] as String?) ?? '',
        title: title,
        longTitle: longTitle,
        duration: (m['duration'] as num?)?.toInt() ?? 0,
        badge: badge,
      ));
    }
    return eps;
  }
  /// 上游调用计数（B19 验收：连播两次 playurl 只能打 1 次）
  final Map<String, int> upstreamCounts = <String, int>{};

  /// 番剧元数据缓存：24 小时（直链 90 分钟一刷，元数据没必要跟着刷）
  final Map<String, _SeasonCacheEntry> _seasonCache =
      <String, _SeasonCacheEntry>{};

  /// 测试用：清掉番剧元数据缓存
  void debugClearSeasonCache() => _seasonCache.clear();

  void _countUpstream(String key) {
    upstreamCounts[key] = (upstreamCounts[key] ?? 0) + 1;
  }

  final Dio _dio;
  late final DateTime Function() _clock;

  String? _imgKey;
  String? _subKey;
  DateTime? _keysFetchedAt;

  /// 密钥 12 小时过期（14 §1.1）
  static const Duration keysTtl = Duration(hours: 12);

  /// 游客 Cookie（SESSDATA 等）由调用方从 SecureStore 取出塞进来
  set cookie(String? value) {
    if (value == null || value.isEmpty) {
      _dio.options.headers.remove('Cookie');
    } else {
      _dio.options.headers['Cookie'] = value;
    }
  }

  /// 未登录也能拿到 key；拿不到就返回 false，调用方降级到不带 wbi 的接口
  Future<bool> ensureKeys({bool force = false}) async {
    final DateTime? at = _keysFetchedAt;
    if (!force &&
        _imgKey != null &&
        _subKey != null &&
        at != null &&
        _clock().difference(at) < keysTtl) {
      return true;
    }
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'https://api.bilibili.com$kNavPath',
      );
      final Map<String, Object?>? root = _asMap(_json(resp.data));
      // nav 的外层是 {code,message,ttl,data}，wbi_img 在 data.data 里面
      final Map<String, Object?>? payload = _asMap(root?['data']);
      // 注意：jsonDecode 出来的是 Map<String, dynamic>，`is Map<String, Object?>` 在 VM 上
      // 会因为泛型实参是 dynamic 而判 false（实测踩过），这里统一过一遍 _asMap。
      final Map<String, Object?>? wbi = _asMap(payload?['wbi_img']);
      if (wbi == null) return false;
      final String imgUrl = (wbi['img_url'] as String?) ?? '';
      final String subUrl = (wbi['sub_url'] as String?) ?? '';
      if (imgUrl.isEmpty || subUrl.isEmpty) return false;
      _imgKey = Wbi.keyFromUrl(imgUrl);
      _subKey = Wbi.keyFromUrl(subUrl);
      _keysFetchedAt = _clock();
      return true;
    } on DioException catch (e) {
      throw _network(e);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ParseException('B 站 WBI 密钥接口', cause: e);
    }
  }

  /// `/x/player/wbi/playurl`：qn 从 [preferredQn] 起按 §1.4 的降级链往下试
  Future<BilibiliPlayInfo> playUrl({
    required String bvid,
    required int cid,
    int preferredQn = 112,
    Map<String, String>? extraParams,
  }) {
    return _playUrlChain(
      path: kPlayUrlPath,
      params: <String, String>{
        'bvid': bvid,
        'cid': '$cid',
        ...?extraParams,
      },
      preferredQn: preferredQn,
      countKey: 'playurl',
    );
  }

  /// `/pgc/player/web/playurl` — 番剧（14 §1.8）
  ///
  /// 走的是同一个 [_playUrlChain] + [_parsePlayInfo]：番剧只是顶层键从 `data`
  /// 换成 `result`，不许另写一份解析（任务硬要求）。
  Future<BilibiliPlayInfo> pgcPlayUrl({
    required int epId,
    required int cid,
    int preferredQn = 112,
  }) {
    return _playUrlChain(
      path: kPgcPlayUrlPath,
      params: <String, String>{
        'ep_id': '$epId',
        'cid': '$cid',
      },
      preferredQn: preferredQn,
      countKey: 'pgc_playurl',
      rootKey: 'result',
      sign: false,
    );
  }

  /// 点播与番剧共用的 qn 降级链 + 解析
  Future<BilibiliPlayInfo> _playUrlChain({
    required String path,
    required Map<String, String> params,
    required int preferredQn,
    required String countKey,
    String rootKey = 'data',
    bool sign = true,
  }) async {
    // 番剧 playurl 不需要 WBI 签名（14 §1.8），带上反而容易被判异常
    final bool signed = sign && await ensureKeys();
    const List<int> fallbackChain = <int>[112, 80, 64, 32, 16, 6];

    // 用户偏好优先，然后按降级链补齐比它低/相等的档
    final List<int> tryQn = <int>[
      preferredQn,
      ...fallbackChain.where((int q) => q < preferredQn),
    ];

    AppException? lastError;
    for (final int qn in tryQn) {
      final Map<String, String> query = <String, String>{
        ...params,
        'qn': '$qn',
        'fnval': '4048',
        'fnver': '0',
        'fourk': '1',
      };
      try {
        _countUpstream(countKey);
        final Map<String, Object?>? payload = signed
            ? await _getSigned(path, query, rootKey: rootKey)
            : await _getPlain(path, query, rootKey: rootKey);
        if (payload == null) continue;
        debugPrint('[YQK-BILI-QN] path=$path qn=$qn code=${payload['code']}');
        // _get 已经按 rootKey 取过一层了（点播 data / 番剧 result），这里不要再取
        final Map<String, Object?> inner = payload;
        final BilibiliPlayInfo? info = _parsePlayInfo(inner);
        if (info != null) return info;
      } on AuthRequiredException catch (e) {
        // -101：未登录，继续往下降（游客最高 480P）
        lastError = e;
      } on RegionLockedException catch (e) {
        // -10403：地区限制，降档没用，直接抛
        throw RegionLockedException(cause: e);
      } on RiskControlException {
        rethrow;
      }
    }
    throw lastError ?? const AuthRequiredException();
  }

  /// `/pgc/view/web/season` — 番剧详情（14 §1.7）
  ///
  /// 顶层是 `result` 不是 `data`；`cid` 在 `episodes[].cid`。
  Future<PgcSeason> pgcSeason({int? epId, int? seasonId}) async {
    if (epId == null && seasonId == null) {
      throw const InvalidSourceException('番剧要 ep 号或季号');
    }
    // 番剧元数据（season/episodes）24 小时缓存：直链 90 分钟一刷，元数据没必要跟着刷
    final String cacheKey = epId != null ? 'ep:$epId' : 'ss:$seasonId';
    final _SeasonCacheEntry? cached = _seasonCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(hours: 24)) {
      debugPrint('[YQK-BILI-SEASON] cache hit key=$cacheKey age='
          '${DateTime.now().difference(cached.at).inMinutes}min');
      return cached.value;
    }
    try {
      _countUpstream('pgc_season');
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'https://api.bilibili.com$kPgcSeasonPath',
        queryParameters: <String, String>{
          if (epId != null) 'ep_id': '$epId',
          if (seasonId != null) 'season_id': '$seasonId',
        },
      );
      final Map<String, Object?> root =
          _asMap(_json(resp.data)) ?? <String, Object?>{};
      final int code = (root['code'] as num?)?.toInt() ?? 0;
      if (code != 0) throw _codeToException(code);
      final Map<String, Object?>? result = _asMap(root['result']);
      if (result == null) throw const ParseException('番剧详情');

      final List<PgcEpisode> eps = BilibiliClient.parsePgcEpisodes(
        (result['episodes'] as List<Object?>?) ?? const <Object?>[],
      );
      if (eps.isEmpty) throw const NotFoundException();
      final PgcSeason season = PgcSeason(
        seasonId: (result['season_id'] as num?)?.toInt() ?? (seasonId ?? 0),
        title: (result['title'] as String?) ?? '',
        cover: (result['cover'] as String?) ?? '',
        episodes: eps,
      );
      _seasonCache[cacheKey] = _SeasonCacheEntry(season, DateTime.now());
      debugPrint('[YQK-BILI-SEASON] 拉取成功 key=$cacheKey 正片 ${eps.length} 集');
      return season;
    } on DioException catch (e) {
      throw _network(e);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ParseException('番剧详情', cause: e);
    }
  }

  /// 直播直链（14 §1.19）：先用新版 getRoomPlayInfo 拼 host+base_url+extra，
  /// 拿不到再退旧版 /room/v1/Room/playUrl 的 durl。
  Future<BilibiliLiveInfo> livePlayUrl(int roomId) async {
    String title = 'B 站直播';
    // 短号（live.bilibili.com/1）要先换成真实 room_id 才能拉流
    int realRoom = roomId;
    try {
      final Response<dynamic> infoResp = await _dio.get<dynamic>(
        '$kLiveBase$kLiveRoomInfoPath',
        queryParameters: <String, String>{'room_id': '$roomId'},
      );
      final Map<String, Object?> infoRoot =
          _asMap(_json(infoResp.data)) ?? <String, Object?>{};
      final Map<String, Object?>? info = _asMap(infoRoot['data']);
      title = (info?['title'] as String?) ?? title;
      final int rid = (info?['room_id'] as num?)?.toInt() ?? 0;
      if (rid > 0) realRoom = rid;
    } on Object {
      // 房间信息拿不到不影响拉流
    }

    try {
      _countUpstream('live_playinfo');
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$kLiveBase$kLivePlayInfoPath',
        queryParameters: <String, String>{
          'room_id': '$realRoom',
          'protocol': '0,1',
          'format': '0,1,2',
          'codec': '0,1',
          'qn': '10000',
          'platform': 'web',
        },
      );
      final Map<String, Object?> root =
          _asMap(_json(resp.data)) ?? <String, Object?>{};
      final int code = (root['code'] as num?)?.toInt() ?? 0;
      if (code == 0) {
        final String? url = _pickLiveUrl(root);
        if (url != null) {
          debugPrint('[YQK-BILI-LIVE] 优先 HLS：'
              '${url.substring(0, url.length > 80 ? 80 : url.length)}');
          return BilibiliLiveInfo(
            url: url,
            roomId: realRoom,
            title: title,
            headers: defaultHeaders,
            expiresAt: _clock().add(const Duration(hours: 2)),
          );
        }
      }
    } on AppException {
      // 落到旧接口
    }

    _countUpstream('live_playurl');
    final Response<dynamic> resp = await _dio.get<dynamic>(
      '$kLiveBase$kLivePlayUrlPath',
      queryParameters: <String, String>{
        'cid': '$realRoom',
        'qn': '10000',
        'platform': 'web',
      },
    );
    final Map<String, Object?> root =
        _asMap(_json(resp.data)) ?? <String, Object?>{};
    final Map<String, Object?>? data = _asMap(root['data']);
    final Object? durl = data?['durl'];
    if (durl is List<Object?> && durl.isNotEmpty) {
      final Map<String, Object?>? first = _asMap(durl.first);
      final String url = (first?['url'] as String?) ?? '';
      if (url.isNotEmpty) {
        debugPrint('[YQK-BILI-LIVE] HLS 拿不到，回退 flv：'
            '${url.substring(0, url.length > 80 ? 80 : url.length)}');
        return BilibiliLiveInfo(
          url: url,
          roomId: roomId,
          title: title,
          headers: defaultHeaders,
          expiresAt: _clock().add(const Duration(hours: 2)),
        );
      }
    }
    throw const NotFoundException();
  }

  /// 从 getRoomPlayInfo 的嵌套结构里挑一条 m3u8：优先 http_hls + ts 格式
  String? _pickLiveUrl(Map<String, Object?> root) {
    final Map<String, Object?>? data = _asMap(root['data']);
    final Map<String, Object?>? playurlInfo = _asMap(data?['playurl_info']);
    final Map<String, Object?>? playurl = _asMap(playurlInfo?['playurl']);
    final Object? streams = playurl?['stream'];
    if (streams is! List<Object?>) return null;

    String? fallback;
    for (final Object? s in streams) {
      final Map<String, Object?>? stream = _asMap(s);
      if (stream == null) continue;
      final String protocol = (stream['protocol_name'] as String?) ?? '';
      final Object? formats = stream['format'];
      if (formats is! List<Object?>) continue;
      for (final Object? f in formats) {
        final Map<String, Object?>? format = _asMap(f);
        if (format == null) continue;
        final Object? codecs = format['codec'];
        if (codecs is! List<Object?>) continue;
        for (final Object? c in codecs) {
          final Map<String, Object?>? codec = _asMap(c);
          if (codec == null) continue;
          final String base = (codec['base_url'] as String?) ?? '';
          final Object? infos = codec['url_info'];
          if (base.isEmpty || infos is! List<Object?> || infos.isEmpty) {
            continue;
          }
          for (final Object? u in infos) {
            final Map<String, Object?>? info = _asMap(u);
            if (info == null) continue;
            final String host = (info['host'] as String?) ?? '';
            final String extra = (info['extra'] as String?) ?? '';
            if (host.isEmpty) continue;
            // host 有时自带 https://，有时是裸域名（14 §1.19）
            final String origin = host.startsWith('http') ? host : 'https://$host';
            final String url = '$origin$base$extra';
            if (protocol.contains('hls') || url.contains('.m3u8')) return url;
            fallback ??= url;
          }
        }
      }
    }
    return fallback;
  }

  /// `/x/player/v2` 取字幕列表，再逐条下载成 [SubtitleData]
  Future<SubtitleData> subtitles({
    required String bvid,
    required int cid,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'https://api.bilibili.com$kPlayerV2Path',
        queryParameters: <String, String>{'bvid': bvid, 'cid': '$cid'},
      );
      final Map<String, Object?> root = _asMap(_json(resp.data)) ?? <String, Object?>{};
      final int code = (root['code'] as num?)?.toInt() ?? 0;
      if (code != 0) {
        // 字幕拿不到不算致命，静默返回空
        return SubtitleData.empty;
      }
      final Map<String, Object?>? data = _asMap(root['data']);
      final Map<String, Object?>? subtitle = _asMap(data?['subtitle']);
      final Object? list = subtitle?['subtitles'];
      if (list is! List<Object?>) return SubtitleData.empty;

      // 优先中文，其次第一条
      Map<String, Object?>? picked;
      for (final Object? item in list) {
        if (item is! Map<String, Object?>) continue;
        final String lan = (item['lan'] as String?) ?? '';
        picked ??= item;
        if (lan.startsWith('zh')) {
          picked = item;
          break;
        }
      }
      if (picked == null) return SubtitleData.empty;
      final String rawUrl = (picked['subtitle_url'] as String?) ?? '';
      if (rawUrl.isEmpty) return SubtitleData.empty;
      // 14 §1.5 的坑：subtitle_url 以 // 开头，要补 https:
      final String url = rawUrl.startsWith('//') ? 'https:$rawUrl' : rawUrl;
      final Response<dynamic> sub = await _dio.get<dynamic>(url);
      final String text = sub.data is String
          ? sub.data as String
          : jsonEncode(sub.data);
      return SubtitleData.fromBilibiliJson(text);
    } on AppException {
      return SubtitleData.empty;
    } on DioException {
      return SubtitleData.empty;
    } catch (e) {
      throw ParseException('B 站字幕接口', cause: e);
    }
  }


  /// `/x/web-interface/wbi/search/type`（14 §1.10）
  Future<List<BilibiliSearchItem>> searchVideos(String keyword,
      {int limit = 20}) async {
    if (!await ensureKeys()) {
      // 拿不到 WBI 密钥就明确说，不假装能搜
      throw const UnsupportedException('B 站搜索（没拿到 WBI 密钥）');
    }
    final Map<String, Object?>? data = await _getSigned(kSearchPath, <String, String>{
      'search_type': 'video',
      'keyword': keyword,
      'page': '1',
      'page_size': '$limit',
      'order': 'totalrank',
    });
    final Object? result = data?['result'];
    if (result is! List<Object?>) return <BilibiliSearchItem>[];
    final List<BilibiliSearchItem> items = <BilibiliSearchItem>[];
    for (final Object? raw in result) {
      final Map<String, Object?>? m = _asMap(raw);
      if (m == null) continue;
      final String bvid = '${m['bvid'] ?? ''}';
      if (bvid.isEmpty) continue;
      items.add(BilibiliSearchItem(
        bvid: bvid,
        // 搜索结果标题里带 <em class="keyword"> 高亮标签，去掉
        title: '${m['title'] ?? ''}'
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll('&amp;', '&')
            .trim(),
        pic: '${m['pic'] ?? ''}'.startsWith('//')
            ? 'https:${m['pic']}'
            : '${m['pic'] ?? ''}',
        durationText: '${m['duration'] ?? ''}',
      ));
    }
    return items;
  }

  // ── 内部 ────────────────────────────────────────────────────────────

  Future<Map<String, Object?>?> _getSigned(
    String path,
    Map<String, String> params, {
    String rootKey = 'data',
  }) async {
    final WbiSignedQuery signed =
        Wbi.sign(params, _imgKey!, _subKey!, wtsSeconds: _nowSeconds());
    // 签名串已经是排好序 + 编码过的，直接拼在 url 后面，不让 Dio 再编码一次
    return _get('https://api.bilibili.com$path?${signed.value}', rootKey: rootKey);
  }

  Future<Map<String, Object?>?> _getPlain(
    String path,
    Map<String, String> params, {
    String rootKey = 'data',
  }) async {
    return _get('https://api.bilibili.com$path',
        queryParameters: params, rootKey: rootKey);
  }

  Future<Map<String, Object?>?> _get(
    String url, {
    Map<String, String>? queryParameters,
    String rootKey = 'data',
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        url,
        queryParameters: queryParameters,
      );
      if (resp.statusCode != null && resp.statusCode! >= 400) {
        throw HttpStatusException(resp.statusCode!);
      }
      final Map<String, Object?>? root = _asMap(_json(resp.data));
      if (root == null) throw const ParseException('B 站接口返回');
      final int code = (root['code'] as num?)?.toInt() ?? 0;
      if (code != 0) throw _codeToException(code);
      return _asMap(root[rootKey]);
    } on DioException catch (e) {
      throw _network(e);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ParseException('B 站接口返回', cause: e);
    }
  }

  int _nowSeconds() => _clock().millisecondsSinceEpoch ~/ 1000;

  /// 错误码 → 人话（14 §1.0 的表）
  AppException _codeToException(int code) {
    switch (code) {
      case -101:
        return const AuthRequiredException();
      case -352:
        return const RiskControlException();
      case -400:
        return const ParseException('B 站说参数不对');
      case -404:
        return const NotFoundException();
      case -10403:
        return const RegionLockedException();
      case 87007:
        return const ContentLockedException();
      case 87008:
        return const ContentLockedException();
      default:
        return AppException('B 站返回了错误码 $code，换一个视频试试');
    }
  }

  AppException _network(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return RequestTimeoutException(cause: e);
      case DioExceptionType.connectionError:
        return NetworkException(cause: e);
      case DioExceptionType.badResponse:
        return HttpStatusException(e.response?.statusCode ?? 0, cause: e);
      default:
        return NetworkException(cause: e);
    }
  }

  BilibiliPlayInfo? _parsePlayInfo(Map<String, Object?> data) {
    final Map<String, Object?>? dash = _asMap(data['dash']);
    final Object? videos = dash?['video'];
    if (videos is! List<Object?> || videos.isEmpty) return null;

    DashStream? best;
    for (final Object? item in videos) {
      final Map<String, Object?>? m = _asMap(item);
      if (m == null) continue;
      final DashStream s = _stream(m);
      if (s.id == 0) continue;
      // 同 id 取码率高的
      if (best == null ||
          s.id > best.id ||
          (s.id == best.id && s.bandwidth > best.bandwidth)) {
        best = s;
      }
    }
    if (best == null) return null;

    final List<DashStream> audios = <DashStream>[];
    final Object? audioList = dash?['audio'];
    if (audioList is List<Object?>) {
      for (final Object? item in audioList) {
        final Map<String, Object?>? m = _asMap(item);
        if (m == null) continue;
        final DashStream s = _stream(m);
        if (s.id != 0) audios.add(s);
      }
    }
    // 30280（192K）优先，没有就码率最高的（14 §1.4 实现要点 2）
    audios.sort((DashStream a, DashStream b) {
      if (a.id == 30280) return -1;
      if (b.id == 30280) return 1;
      return b.bandwidth.compareTo(a.bandwidth);
    });

    return BilibiliPlayInfo(
      video: best,
      audios: audios,
      quality: (data['quality'] as num?)?.toInt() ?? best.id,
      headers: defaultHeaders,
      videoCount: videos.length,
    );
  }

  DashStream _stream(Map<String, Object?> m) {
    final String url =
        (m['baseUrl'] as String?) ?? (m['base_url'] as String?) ?? '';
    return DashStream(
      id: (m['id'] as num?)?.toInt() ?? 0,
      url: url,
      bandwidth: (m['bandwidth'] as num?)?.toInt() ?? 0,
      codecs: (m['codecs'] as String?) ?? '',
      width: (m['width'] as num?)?.toInt() ?? 0,
      height: (m['height'] as num?)?.toInt() ?? 0,
    );
  }

  static Object? _json(Object? data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  static Map<String, Object?>? _asMap(Object? v) {
    if (v is Map<String, Object?>) return v;
    if (v is Map<Object?, Object?>) {
      return v.map<String, Object?>(
        (Object? k, Object? value) => MapEntry<String, Object?>('$k', value),
      );
    }
    return null;
  }
}
