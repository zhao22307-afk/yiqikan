/// 分享文案识别（15 §B21 / 13 §B21）。
///
/// 用户从微信/QQ/抖音复制来的都是「一句废话 + 一个链接 + 一堆表情」，
/// 这里只干两件事：挑出第一个 http(s) 链接；如果整段话里没有链接、只有裸 BV 号，
/// 就把它拼成 B 站地址。
library;

/// 识别出来的平台
enum SharePlatform {
  bilibiliVideo('B 站视频'),
  bilibiliBangumi('B 站番剧'),
  bilibiliLive('B 站直播'),
  douyin('抖音'),
  kuaishou('快手'),
  xiaohongshu('小红书'),
  maccms('采集站'),
  netdisk('网盘'),
  unknown('未知来源');

  const SharePlatform(this.label);

  final String label;
}

/// 一条分享链接
class ShareLink {
  const ShareLink({required this.url, required this.platform});

  final String url;
  final SharePlatform platform;

  @override
  String toString() => 'ShareLink($platform, $url)';
}

/// 从一段文字里提第一个 http(s) 链接，并判断平台
class ShareLinkParser {
  ShareLinkParser._();

  /// 链接本体：到空白或中文标点为止（微信文案里常见「，」「！」「http」贴在一起）
  static final RegExp _url = RegExp(
    r'https?://[^\s，。！？、；：""''（）【】《》<>|]+',
  );

  /// 裸 BV 号（没有链接时兜底）
  static final RegExp _bareBvid = RegExp(r'BV[0-9A-Za-z]{10}');

  static final RegExp _epLink = RegExp(r'/bangumi/play/ep(\d+)');
  static final RegExp _epQuery = RegExp(r'[?&]ep_id=\d+');
  static final RegExp _liveRoom = RegExp(r'live\.bilibili\.com/');
  static final RegExp _douyin =
      RegExp(r'(v\.douyin\.com|www\.douyin\.com|www\.iesdouyin\.com)');
  static final RegExp _kuaishou =
      RegExp(r'(v\.kuaishou\.com|www\.kuaishou\.com|chenzhongtech\.com)');
  static final RegExp _xiaohongshu =
      RegExp(r'(xhslink\.com|www\.xiaohongshu\.com)');
  static final RegExp _maccms = RegExp(r'(/index\.php/vod/|/voddetail/|/detail/)');
  static final RegExp _netdisk = RegExp(
    r'(pan\.quark\.cn|115\.com|115cdn\.com|123pan\.com|cloud\.189\.cn|alipan\.com)',
  );

  /// 整段文字 → 链接（提不到返回 null）
  static String? extractUrl(String text) {
    if (text.trim().isEmpty) return null;
    final RegExpMatch? m = _url.firstMatch(text);
    if (m != null) return _trimTail(m.group(0)!);
    // 没有链接时，允许裸 BV 号
    final String? bv = _bareBvid.firstMatch(text)?.group(0);
    if (bv != null) return 'https://www.bilibili.com/video/$bv';
    return null;
  }

  /// 提取 + 判平台
  static ShareLink? parse(String text) {
    final String? url = extractUrl(text);
    if (url == null) return null;
    return ShareLink(url: url, platform: platformOf(url));
  }

  /// 按 URL 猜平台
  static SharePlatform platformOf(String url) {
    final String u = url.toLowerCase();
    if (_liveRoom.hasMatch(u)) return SharePlatform.bilibiliLive;
    if (_epLink.hasMatch(u) || _epQuery.hasMatch(u)) {
      return SharePlatform.bilibiliBangumi;
    }
    if (u.contains('bilibili.com') || u.contains('b23.tv')) {
      return SharePlatform.bilibiliVideo;
    }
    if (_douyin.hasMatch(u)) return SharePlatform.douyin;
    if (_kuaishou.hasMatch(u)) return SharePlatform.kuaishou;
    if (_xiaohongshu.hasMatch(u)) return SharePlatform.xiaohongshu;
    if (_netdisk.hasMatch(u)) return SharePlatform.netdisk;
    if (_maccms.hasMatch(u)) return SharePlatform.maccms;
    return SharePlatform.unknown;
  }

  /// 去掉尾巴上的英文标点（`),` `."` 这类从句子末尾带进来的）
  static String _trimTail(String url) {
    String out = url;
    const String tail = '),.;:!?\'"';
    while (out.isNotEmpty && tail.contains(out[out.length - 1])) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }
}
