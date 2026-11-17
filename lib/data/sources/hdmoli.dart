import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logger.dart';
import 'maccms.dart' show MacCmsEpisode, MacCmsItem, MacCmsLine;

/// 网页型片源：HDmoli（MacCMS 模板站，但只有 HTML 页面，没有 JSON 接口）
///
/// 这一层只做「站点结构 → 统一的 MacCmsItem 形态」：
/// 搜索页、详情页都解析成 [MacCmsItem]，播放页 URL 原样交出去 —— 真正的
/// 播放地址（m3u8）由现有嗅探链路去取，这里不写任何嗅探逻辑。
class HdmoliSource {
  HdmoliSource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: kHttpConnectTimeout,
              receiveTimeout: kHttpReadTimeout,
              followRedirects: true,
              validateStatus: (int? s) => s != null && s < 500,
            ));

  static const String _origin = 'https://www.hdmoli.me';
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 每个请求都带：站点按 Referer 判来源，缺了会直接给空页
  static Map<String, String> get headers => <String, String>{
        'User-Agent': _ua,
        'Referer': '$_origin/',
      };

  /// 播放时补进 PlayerMedia.headers 的那一份（A4 用）
  static Map<String, String> get playHeaders => <String, String>{
        'Referer': '$_origin/',
        'User-Agent': _ua,
      };

  static String get origin => _origin;

  static HdmoliSource? _inst;

  /// 片源页/服务共用的一个实例（play 校验不碰网络，但省得每次 new Dio）
  static HdmoliSource get instance => _inst ??= HdmoliSource();

  final Dio _dio;

  /// 搜索（只取第一页）
  Future<List<MacCmsItem>> search(String keyword) async {
    final String kw = keyword.trim();
    if (kw.isEmpty) return <MacCmsItem>[];
    final String url =
        '$_origin/search/-------------.html?wd=${Uri.encodeComponent(kw)}';
    final dom.Document doc = await _get(url);
    final List<MacCmsItem> items = <MacCmsItem>[];
    for (final dom.Element el
        in doc.querySelectorAll('.myui-vodlist__box, .myui-vodlist__media > li')) {
      final dom.Element? a = el.querySelector('.myui-vodlist__thumb');
      final String name = a?.attributes['title']?.trim() ?? '';
      final String href = a?.attributes['href'] ?? '';
      final String image = a?.attributes['data-original'] ?? '';
      final String label = el.querySelector('.pic-text')?.text.trim() ?? '';
      final String score = el.querySelector('.pic-tag')?.text.trim() ?? '';
      final RegExpMatch? m = RegExp(r'/movie/index(\d+)\.html').firstMatch(href);
      if (m == null || name.isEmpty) continue;
      items.add(MacCmsItem(
        id: m.group(1)!,
        name: name,
        pic: image,
        remarks: <String>[score, label].where((String s) => s.isNotEmpty).join(' · '),
      ));
    }
    final bool hasNext = doc.querySelector('.myui-page a[href*="page"]') != null ||
        doc.querySelector('.myui-page a:last-child')?.text.contains('下一页') == true;
    debugPrint('[YQK-SRC] hdmoli search kw=$kw n=${items.length} next=$hasNext');
    AppLog.add('[YQK-SRC] hdmoli search kw=$kw n=${items.length}');
    return items;
  }

  /// 详情：作品 id → 名称 / 简介 / 线路 + 剧集
  Future<MacCmsItem> detail(String id) async {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      throw const AppException('HDmoli 作品 id 不合法');
    }
    final dom.Document doc = await _get('$_origin/movie/index$id.html');

    final String name =
        doc.querySelector('.myui-content__thumb .picture')?.attributes['title']?.trim() ??
            doc.querySelector('.myui-content__detail h1')?.text.trim() ??
            '';
    if (name.isEmpty) {
      throw const AppException('HDmoli 详情暂时不可用');
    }
    final String pic = doc
            .querySelector('.myui-content__thumb .picture img')
            ?.attributes['data-original'] ??
        '';
    final String intro = _introOf(doc);

    final List<MacCmsLine> lines = <MacCmsLine>[];
    int episodes = 0;
    for (final dom.Element tab in doc.querySelectorAll('a[href^="#playlist"]')) {
      final String h = tab.attributes['href'] ?? '';
      if (!RegExp(r'^#playlist\d+$').hasMatch(h)) continue;
      final String tabText = tab.text.trim();
      if (RegExp(r'网盘|夸克|迅雷|百度|阿里|天翼|磁力|quark|xunlei', caseSensitive: false)
          .hasMatch(tabText)) {
        // 网盘线路给的是分享页，不是播放页：整行跳过
        continue;
      }
      final List<MacCmsEpisode> eps = <MacCmsEpisode>[];
      for (final dom.Element row in doc.querySelectorAll('$h .myui-content__list a')) {
        final String href = row.attributes['href'] ?? '';
        final RegExpMatch? m =
            RegExp(r'^/play/(\d+)-(\d+)-(\d+)\.html$').firstMatch(href);
        if (m == null || m.group(1) != id) continue;
        final String full = Uri.parse(_origin).resolve(href).toString();
        eps.add(MacCmsEpisode(
          name: row.text.trim().isEmpty ? '第 ${eps.length + 1} 集' : row.text.trim(),
          url: full,
        ));
      }
      if (eps.isEmpty) continue;
      episodes += eps.length;
      lines.add(MacCmsLine(
        name: tabText.isEmpty ? '线路 ${lines.length + 1}' : tabText,
        episodes: eps,
      ));
    }
    debugPrint('[YQK-SRC] hdmoli detail id=$id lines=${lines.length} eps=$episodes');
    AppLog.add('[YQK-SRC] hdmoli detail id=$id lines=${lines.length} eps=$episodes');
    return MacCmsItem(
      id: id,
      name: name,
      pic: pic,
      remarks: '',
      content: intro,
      lines: lines,
    );
  }

  /// 播放：只做「是不是本站」的校验，返回原播放页地址（嗅探由上层负责）
  String play(String episodeUrl) {
    final Uri? uri = Uri.tryParse(episodeUrl.trim());
    if (uri == null) {
      throw const AppException('HDmoli 播放地址不合法');
    }
    if (uri.host != Uri.parse(_origin).host) {
      // 防跳站：站点内容里混进别的域名时不跟过去
      throw const AppException('HDmoli 返回了非本站页面');
    }
    debugPrint('[YQK-SRC] hdmoli play url=${uri.path}');
    return episodeUrl.trim();
  }

  // ── 内部 ────────────────────────────────────────────────────────────

  Future<dom.Document> _get(String url) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>(url, options: Options(headers: headers));
      if (resp.statusCode != null && resp.statusCode! >= 400) {
        throw HttpStatusException(resp.statusCode!);
      }
      final String body = '${resp.data ?? ''}';
      if (body.isEmpty) throw const ParseException('HDmoli 返回的网页');
      return html_parser.parse(body);
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw RequestTimeoutException(cause: e);
        case DioExceptionType.badResponse:
          throw HttpStatusException(e.response?.statusCode ?? 0, cause: e);
        default:
          debugPrint('[YQK-SRC] hdmoli net fail url=$url type=${e.type} msg=${e.message}');
          throw NetworkException(cause: e);
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw ParseException('HDmoli 返回的网页', cause: e);
    }
  }

  /// 详情页的简介：详情块里「简介：」之后那段
  static String _introOf(dom.Document doc) {
    final String all = doc.querySelector('.myui-content__detail')?.text ?? '';
    final int i = all.indexOf('简介：');
    if (i < 0) return '';
    String s = all.substring(i + 3).trim();
    for (final String stop in <String>['收起', '详情', '展开']) {
      final int j = s.indexOf(stop);
      if (j > 0) s = s.substring(0, j);
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 400 ? s.substring(0, 400) : s;
  }
}
