import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/errors/app_exception.dart';
import 'package:yiqikan/data/sources/hdmoli.dart';
import 'package:yiqikan/data/sources/maccms.dart';

/// 不联网的 Dio：请求直接回一段固定 HTML
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.status = 200});

  final String body;
  final int status;
  final List<String> urls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    urls.add(options.uri.toString());
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HdmoliSource _src(String html, {int status = 200}) {
  final Dio dio = Dio()..httpClientAdapter = _FakeAdapter(html, status: status);
  return HdmoliSource(dio: dio);
}

const String _searchHtml = '''
<ul class="myui-vodlist__media clearfix" id="searchList">
  <li>
    <div class="thumb">
      <a class="myui-vodlist__thumb" href="/movie/index1477.html" title="流浪地球"
         data-original="https://img.example/a.jpg"></a>
    </div>
    <div class="content">
      <span class="pic-tag pic-tag-right">7.9分</span>
      <span class="pic-text text-left">No.2华语冒险片榜</span>
    </div>
  </li>
  <li>
    <div class="thumb">
      <a class="myui-vodlist__thumb" href="/movie/index2001.html" title="流浪地球2"
         data-original="https://img.example/b.jpg"></a>
    </div>
    <div class="content">
      <span class="pic-text text-left">HD</span>
    </div>
  </li>
  <li>
    <div class="thumb">
      <a class="myui-vodlist__thumb" href="/voddetail/999.html" title="不是作品页"></a>
    </div>
  </li>
</ul>
''';

const String _detailHtml = '''
<div class="myui-content__thumb">
  <a class="myui-vodlist__thumb picture" href="/play/1477-1-1.html" title="流浪地球">
    <img class="lazyload" data-original="https://img.example/p.jpg"/>
  </a>
</div>
<div class="myui-content__detail">
  <h1 class="title text-fff">流浪地球 <font>No.2华语冒险片榜</font></h1>
  <div class="text-muted">简介： 太阳即将毁灭，人类在地球表面建造出巨大的推进器。</div>
</div>
<div class="myui-panel">
  <a href="#playlist0">线路1</a>
  <a href="#playlist1">线路2</a>
  <a href="#playlist3">夸克网盘</a>
  <a href="#other">不是线路</a>
</div>
<div id="playlist0" class="tab-pane fade in clearfix">
  <ul class="myui-content__list sort-list clearfix">
    <li><a href="/play/1477-6-1.html">第01集</a></li>
  </ul>
</div>
<div id="playlist1" class="tab-pane fade in clearfix">
  <ul class="myui-content__list sort-list clearfix">
    <li><a href="/play/1477-1-1.html">1080p</a></li>
    <li><a href="/play/1477-1-2.html">1080p 第2集</a></li>
  </ul>
</div>
<div id="playlist3" class="tab-pane fade in clearfix">
  <ul class="myui-content__list sort-list clearfix">
    <li><a href="/play/1477-2-1.html">网盘</a></li>
  </ul>
</div>
''';

void main() {
  group('HdmoliSource.search', () {
    test('解析出作品条目：id / 名称 / 封面 / 备注', () async {
      final List<MacCmsItem> items = await _src(_searchHtml).search('流浪地球');
      expect(items.length, 2);
      expect(items.first.id, '1477');
      expect(items.first.name, '流浪地球');
      expect(items.first.pic, 'https://img.example/a.jpg');
      expect(items.first.remarks, contains('7.9分'));
      expect(items[1].id, '2001');
      expect(items[1].name, '流浪地球2');
    });

    test('不是作品页的链接被跳过', () async {
      final List<MacCmsItem> items = await _src(_searchHtml).search('流浪地球');
      expect(items.any((MacCmsItem i) => i.id == '999'), isFalse);
    });

    test('空关键词不发请求', () async {
      final Dio dio = Dio();
      final _FakeAdapter ad = _FakeAdapter(_searchHtml);
      dio.httpClientAdapter = ad;
      final List<MacCmsItem> items = await HdmoliSource(dio: dio).search('   ');
      expect(items, isEmpty);
      expect(ad.urls, isEmpty);
    });
  });

  group('HdmoliSource.detail', () {
    test('线路与剧集：跳过网盘线路，只要本作品的播放页', () async {
      final MacCmsItem item = await _src(_detailHtml).detail('1477');
      expect(item.name, '流浪地球');
      expect(item.pic, 'https://img.example/p.jpg');
      expect(item.content, contains('推进器'));
      expect(item.lines.length, 2);
      expect(item.lines.first.name, '线路1');
      expect(item.lines.first.episodes.single.name, '第01集');
      expect(
        item.lines.first.episodes.single.url,
        'https://www.hdmoli.me/play/1477-6-1.html',
      );
      expect(item.lines[1].episodes.length, 2);
      expect(
        item.lines[1].episodes.first.url,
        'https://www.hdmoli.me/play/1477-1-1.html',
      );
    });

    test('id 不合法直接抛，不发请求', () async {
      final Dio dio = Dio();
      final _FakeAdapter ad = _FakeAdapter(_detailHtml);
      dio.httpClientAdapter = ad;
      final HdmoliSource s = HdmoliSource(dio: dio);
      await expectLater(
        s.detail('abc'),
        throwsA(isA<AppException>()
            .having((AppException e) => e.userMessage, 'userMessage',
                contains('不合法'))),
      );
      await expectLater(s.detail('0'), throwsA(isA<AppException>()));
      expect(ad.urls, isEmpty);
    });
  });

  group('HdmoliSource.play', () {
    test('本站播放页原样返回', () {
      const String u = 'https://www.hdmoli.me/play/1477-1-1.html';
      expect(HdmoliSource.instance.play(u), u);
    });

    test('非本站 host 抛「HDmoli 返回了非本站页面」', () {
      expect(
        () => HdmoliSource.instance.play('https://evil.example/play/1477-1-1.html'),
        throwsA(isA<AppException>().having(
            (AppException e) => e.userMessage, 'userMessage', 'HDmoli 返回了非本站页面')),
      );
    });
  });
}
