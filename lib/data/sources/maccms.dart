import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logger.dart';

/// 一集
class MacCmsEpisode {
  const MacCmsEpisode({required this.name, required this.url});

  final String name;
  final String url;
}

/// 一条 MacCMS 记录（14 §13）
class MacCmsItem {
  const MacCmsItem({
    required this.id,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.year = '',
    this.area = '',
    this.content = '',
    this.lines = const <MacCmsLine>[],
  });

  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String year;
  final String area;
  final String content;

  /// 播放线路（`vod_play_from` 的每一段）
  final List<MacCmsLine> lines;

  /// 第一条有剧集的线路
  MacCmsLine? get firstPlayableLine {
    for (final MacCmsLine l in lines) {
      if (l.episodes.isNotEmpty) return l;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'pic': pic,
        'remarks': remarks,
        'year': year,
        'area': area,
        'content': content,
        'lines': lines
            .map((MacCmsLine l) => <String, Object?>{
                  'name': l.name,
                  'episodes': l.episodes
                      .map((MacCmsEpisode e) =>
                          <String, Object?>{'name': e.name, 'url': e.url})
                      .toList(),
                })
            .toList(),
      };
}

/// 一条线路
class MacCmsLine {
  const MacCmsLine({required this.name, required this.episodes});

  final String name;
  final List<MacCmsEpisode> episodes;
}

/// MacCMS 采集站解析（14 §13）
///
/// 只承诺「第一条线路的第一集能直接出链」这一种形态；其它形态明确抛
/// [UnsupportedException]，不装作能兼容（06 §8.2 的跑偏信号）。
class MacCmsParser {
  MacCmsParser({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              headers: const <String, String>{
                'Accept': 'application/json, text/xml, */*',
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
                        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              },
              validateStatus: (int? s) => s != null && s < 500,
            ));

  final Dio _dio;

  /// 搜索：`?ac=detail&wd=` 一次拿全（14 §13.3）
  Future<List<MacCmsItem>> search(String apiUrl, String keyword) async {
    final String url = _withQuery(apiUrl, <String, String>{
      'ac': 'detail',
      'wd': keyword,
    });
    return _fetchList(url);
  }

  /// 详情：`?ac=detail&ids=`
  Future<MacCmsItem?> detail(String apiUrl, String id) async {
    final String url = _withQuery(apiUrl, <String, String>{
      'ac': 'detail',
      'ids': id,
    });
    final List<MacCmsItem> list = await _fetchList(url);
    return list.isEmpty ? null : list.first;
  }

  /// 按 14 §13.2 的三层分隔解析 `vod_play_from` / `vod_play_url`
  static List<MacCmsLine> parseLines(String from, String urlField) {
    final List<String> names = from.split(r'$$$');
    final List<String> groups = urlField.split(r'$$$');
    final List<MacCmsLine> lines = <MacCmsLine>[];
    for (int i = 0; i < groups.length; i++) {
      final String group = groups[i].trim();
      if (group.isEmpty) continue;
      final String lineName = i < names.length && names[i].trim().isNotEmpty
          ? names[i].trim()
          : '线路 ${i + 1}';
      final List<MacCmsEpisode> episodes = <MacCmsEpisode>[];
      for (final String raw in group.split('#')) {
        final String piece = raw.trim();
        if (piece.isEmpty) continue;
        final int dollar = piece.indexOf(r'$');
        if (dollar <= 0) {
          // 没有「名$地址」，只有地址：当成第 N 集
          if (piece.startsWith('http')) {
            episodes.add(MacCmsEpisode(
              name: '第 ${episodes.length + 1} 集',
              url: piece,
            ));
          }
          continue;
        }
        final String name = piece.substring(0, dollar).trim();
        final String url = piece.substring(dollar + 1).trim();
        if (url.isEmpty) continue;
        episodes.add(MacCmsEpisode(
          name: name.isEmpty ? '第 ${episodes.length + 1} 集' : name,
          url: url,
        ));
      }
      lines.add(MacCmsLine(name: lineName, episodes: episodes));
    }
    return lines;
  }

  /// 只取「第一条线路第一集」，并且要求它是能直接播的地址
  ///
  /// 命中不了就抛 [UnsupportedException]，日志里写清楚是哪一条不满足。
  static String firstEpisodeUrl(MacCmsItem item) {
    final MacCmsLine? line = item.firstPlayableLine;
    if (line == null) {
      AppLog.add('[YQK-MACCMS] ${item.name} 没有任何线路有剧集');
      throw const UnsupportedException('这个采集站返回的播放线路');
    }
    final MacCmsEpisode ep = line.episodes.first;
    final String url = ep.url;
    final bool looksDirect = url.startsWith('http') &&
        (url.contains('.m3u8') ||
            url.contains('.mp4') ||
            url.contains('.flv') ||
            url.contains('.mkv') ||
            url.contains('.ts'));
    if (!looksDirect) {
      // 形如 "https://www.bilibili.com/video/BVxxx" 这种是「跳转源」，要先解析
      AppLog.add('[YQK-MACCMS] ${item.name} 第一集不是直链：$url');
      throw UnsupportedException('采集站这种跳转式播放地址（${line.name}）');
    }
    return url;
  }

  // ── 内部 ────────────────────────────────────────────────────────────

  Future<List<MacCmsItem>> _fetchList(String url) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(url);
      if (resp.statusCode != null && resp.statusCode! >= 400) {
        throw HttpStatusException(resp.statusCode!);
      }
      final Map<String, Object?>? root = _asMap(resp.data);
      if (root == null) throw const ParseException('采集站返回');
      final Object? list = root['list'];
      if (list is! List<Object?>) throw const ParseException('采集站的片单');
      final List<MacCmsItem> items = <MacCmsItem>[];
      for (final Object? raw in list) {
        final Map<String, Object?>? m = _asMap(raw);
        if (m == null) continue;
        items.add(MacCmsItem(
          id: '${m['vod_id'] ?? ''}',
          name: '${m['vod_name'] ?? '未命名'}',
          pic: '${m['vod_pic'] ?? ''}',
          remarks: '${m['vod_remarks'] ?? ''}',
          year: '${m['vod_year'] ?? ''}',
          area: '${m['vod_area'] ?? ''}',
          content: '${m['vod_content'] ?? ''}',
          lines: parseLines(
            '${m['vod_play_from'] ?? ''}',
            '${m['vod_play_url'] ?? ''}',
          ),
        ));
      }
      return items;
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw RequestTimeoutException(cause: e);
        case DioExceptionType.badResponse:
          throw HttpStatusException(e.response?.statusCode ?? 0, cause: e);
        default:
          throw NetworkException(cause: e);
      }
    } on AppException {
      rethrow;
    } catch (e) {
      if (e is FormatException) {
        throw ParseException('采集站返回', cause: e);
      }
      throw ParseException('采集站返回', cause: e);
    }
  }

  static String _withQuery(String base, Map<String, String> params) {
    final Uri uri = Uri.parse(base);
    final Map<String, String> merged = <String, String>{
      ...uri.queryParameters,
      ...params,
    };
    return uri.replace(queryParameters: merged).toString();
  }

  static Map<String, Object?>? _asMap(Object? v) {
    if (v is Map<String, Object?>) return v;
    if (v is String) {
      try {
        final Object? decoded = jsonDecode(v);
        return _asMap(decoded);
      } catch (_) {
        return null;
      }
    }
    if (v is Map<Object?, Object?>) {
      return v.map<String, Object?>(
        (Object? k, Object? value) => MapEntry<String, Object?>('$k', value),
      );
    }
    return null;
  }
}
