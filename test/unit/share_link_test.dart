import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/share_link.dart';

void main() {
  // 15 §B21：用户从各平台复制来的整段话，只挑链接
  const List<String> texts = <String>[
    '【哔哩哔哩】 鬼灭之刃 柱训练篇 第1话 https://www.bilibili.com/bangumi/play/ep826497?share_source=copy_web 快来看',
    '复制打开抖音，看看【某某的作品】 https://v.douyin.com/iRxKqA1T/ 复制此链接，打开Dou音搜索',
    '快手极速版，看看这个 https://v.kuaishou.com/2xAbCd 复制此消息',
    '48 小红书，发现好东西！ https://www.xiaohongshu.com/discovery/item/66f1a2b3c4d5e6f7a8b9c0d1',
    '老片回看：https://demo.example.com/index.php/vod/detail/id/12345.html',
    '只有 BV 号没链接 BV15i421v7FQ 自己搜',
  ];

  test('share text → first url, 4 个平台都能认', () {
    final List<String?> urls = texts.map(ShareLinkParser.extractUrl).toList();
    for (int i = 0; i < texts.length; i++) {
      // 打印出来贴验收用
      // ignore: avoid_print
      print('[share] case$i → ${urls[i]} ${ShareLinkParser.parse(texts[i])?.platform.label}');
    }
    expect(urls[0], contains('bilibili.com/bangumi/play/ep826497'));
    expect(urls[1], contains('v.douyin.com/iRxKqA1T'));
    expect(urls[2], contains('v.kuaishou.com/2xAbCd'));
    expect(urls[3], contains('xiaohongshu.com/discovery/item/'));
    expect(urls[4], contains('/vod/detail/id/12345.html'));
    expect(urls[5], 'https://www.bilibili.com/video/BV15i421v7FQ');
  });

  test('platform 判定', () {
    expect(
      ShareLinkParser.platformOf('https://www.bilibili.com/bangumi/play/ep826497'),
      SharePlatform.bilibiliBangumi,
    );
    expect(
      ShareLinkParser.platformOf('https://live.bilibili.com/7734200'),
      SharePlatform.bilibiliLive,
    );
    expect(
      ShareLinkParser.platformOf('https://b23.tv/abcDEF'),
      SharePlatform.bilibiliVideo,
    );
    expect(
      ShareLinkParser.platformOf('https://pan.quark.cn/s/deadbeef'),
      SharePlatform.netdisk,
    );
  });

  test('中文标点粘连不会把句号吃进 URL', () {
    final String? u =
        ShareLinkParser.extractUrl('看这个 https://b23.tv/xyz123，挺好玩的');
    expect(u, 'https://b23.tv/xyz123');
  });
}
