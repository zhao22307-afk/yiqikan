import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/features/player/playlist_frame.dart';

/// 第 38 轮 V6：房主/旧客户端只发 url、不带 urls 的 media 帧，
/// 客人侧必须「只切这一条」而不是崩 —— 解析函数返回空表，调用方跳过 setPlaylist。
void main() {
  test('旧帧只有 url：片单为空，不抛异常', () {
    final List<dynamic> pl = playlistFromMediaFrame(<String, dynamic>{
      'type': 'media',
      'url': 'http://127.0.0.1:8099/ep1.mp4',
      'title': 'LocalTestDrama',
    });
    expect(pl, isEmpty);
  });

  test('urls 为空表也当没有片单', () {
    expect(
      playlistFromMediaFrame(<String, dynamic>{
        'url': 'http://127.0.0.1:8099/ep1.mp4',
        'urls': <String>[],
      }),
      isEmpty,
    );
  });

  test('带 urls/titles：按顺序建片单，短 titles 用「第 N 集」兜底', () {
    final List pl = playlistFromMediaFrame(<String, dynamic>{
      'url': 'http://h/ep1.mp4',
      'urls': <String>['http://h/ep1.mp4', 'http://h/ep2.mp4', 'http://h/ep3.mp4'],
      'titles': <String>['第一集'],
      'sourceKind': 'maccms',
      'sourceId': '77',
    });
    expect(pl, hasLength(3));
    expect(pl[0].id, 'http://h/ep1.mp4');
    expect(pl[0].title, '第一集');
    expect(pl[1].title, '第 2 集');
    expect(pl[2].title, '第 3 集');
    expect(pl[2].sourceKind, 'maccms');
    expect(pl[2].sourceId, '77');
  });

  test('urls 里的空串被跳过', () {
    final List pl = playlistFromMediaFrame(<String, dynamic>{
      'urls': <String>['', 'http://h/ep2.mp4'],
    });
    expect(pl, hasLength(1));
    expect(pl.single.url, 'http://h/ep2.mp4');
  });
}
