import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/download/download_task.dart';

void main() {
  test('DownloadTask JSON 往返：received/total/state 都保留', () {
    final DownloadTask t = DownloadTask(
      id: 'abc123',
      url: 'http://x/a.mp4',
      title: '测试片',
      savePath: '/tmp/abc123.mp4',
    )
      ..received = 1024
      ..total = 4096
      ..state = DownloadState.paused
      ..speedKbps = 12.5;

    final String blob = DownloadTask.encodeList(<DownloadTask>[t]);
    final List<DownloadTask> back = DownloadTask.decodeList(blob);

    expect(back.length, 1);
    expect(back.first.url, 'http://x/a.mp4');
    expect(back.first.received, 1024);
    expect(back.first.total, 4096);
    expect(back.first.state, DownloadState.paused);
    expect(back.first.progress, closeTo(0.25, 1e-9));
  });

  test('re 恢复：running 落盘后读回变 paused（进程死掉不会假装还在下）', () {
    final DownloadTask t = DownloadTask(
      id: 'r1',
      url: 'http://x/b.mkv',
      title: 'b',
      savePath: '/tmp/r1.mkv',
    )..state = DownloadState.running;

    final List<DownloadTask> back =
        DownloadTask.decodeList(DownloadTask.encodeList(<DownloadTask>[t]));
    expect(back.single.state, DownloadState.paused);
  });

  test('total=-1（服务器没给 Content-Length）时 progress 为 0，不除零', () {
    final DownloadTask t = DownloadTask(
      id: 'n1',
      url: 'http://x/c.ts',
      title: 'c',
      savePath: '/tmp/n1.ts',
    )..received = 999;
    expect(t.total, -1);
    expect(t.progress, 0);
    expect(DownloadTask.sizeText(-1), '未知');
    expect(DownloadTask.sizeText(0), '0 B');
  });

  test('decodeList 容错：null / 坏 JSON 返回空表', () {
    expect(DownloadTask.decodeList(null), isEmpty);
    expect(DownloadTask.decodeList('not json'), isEmpty);
    expect(DownloadTask.decodeList('[]'), isEmpty);
  });
}
