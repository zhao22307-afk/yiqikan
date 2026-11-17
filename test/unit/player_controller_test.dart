import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/data/db/app_database.dart';
import 'package:yiqikan/domain/media_chapter.dart';
import 'package:yiqikan/features/player/player_controller.dart';
import 'package:yiqikan/platform/player/playback_kernel.dart';

/// 假内核：只发事件、不碰真实解码，用来验证控制器这一层的契约。
class FakeKernel implements PlaybackKernel {
  final StreamController<Duration> _pos = StreamController<Duration>.broadcast();
  final StreamController<Duration> _dur = StreamController<Duration>.broadcast();
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _buffering = StreamController<bool>.broadcast();
  final StreamController<String> _err = StreamController<String>.broadcast();

  final List<String> openedUrls = <String>[];
  final Map<String, String> properties = <String, String>{};
  Duration openedAt = Duration.zero;
  double rate = 1;
  String? subtitlePath;
  double subDelay = 0;
  double subFontSize = 42;
  bool disposed = false;
  bool pauseCalled = false;

  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;

  @override
  double? get videoAspect => aspectValue;
  double? aspectValue;

  @override
  String get name => 'fake';

  @override
  Stream<PlaybackEvent> get events => const Stream<PlaybackEvent>.empty();

  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration> get durationStream => _dur.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<String> get errorStream => _err.stream;

  @override
  bool get buffering => false;

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) => const SizedBox.shrink();

  @override
  Future<void> open(
    String url, {
    MediaOpenOptions options = MediaOpenOptions.none,
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    openedUrls.add(url);
    openedAt = start;
    position = start;
  }

  void emitPosition(Duration p) {
    position = p;
    _pos.add(p);
  }

  void emitDuration(Duration d) {
    duration = d;
    _dur.add(d);
  }

  @override
  bool get playing => false;

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {
    pauseCalled = true;
  }

  @override
  Future<void> seek(Duration d) async => position = d;

  @override
  Future<void> setRate(double r) async => rate = r;

  @override
  Future<void> setVolume(double v) async {}

  @override
  Future<void> setSubtitle(String? path, {String? title}) async =>
      subtitlePath = path;

  @override
  Future<void> setSubDelay(double seconds) async => subDelay = seconds;

  @override
  Future<void> setSubFontSize(double size) async => subFontSize = size;

  @override
  List<String> get audioTrackNames => <String>['默认'];

  @override
  int get currentAudioTrack => 0;

  @override
  List<AudioTrackInfo> get audioTracks => <AudioTrackInfo>[
        const AudioTrackInfo(index: 0, label: '默认音轨', channels: 2),
      ];

  @override
  Future<void> setAspectRatio(double ratio) async =>
      properties['video-aspect-override'] = ratio <= 0 ? '-1' : '$ratio';

  @override
  bool get supportsSubtitleTuning => true;

  @override
  Future<Map<String, String?>> debugProperties(List<String> keys) async =>
      <String, String?>{for (final String k in keys) k: properties[k]};

  @override
  Future<void> setAudioTrack(int index) async {}

  @override
  Future<void> addExternalAudio(String path) async =>
      properties['audio-file'] = path;

  @override
  Future<void> selectLastAudioTrack() async {}

  @override
  List<String> get subtitleTrackNames => const <String>[];

  @override
  Future<void> setSubtitleTrack(int index) async {}

  @override
  bool get supportsProperties => true;

  /// H4：假内核没有章节
  @override
  Future<List<MediaChapter>> chapters() async => const <MediaChapter>[];

  @override
  Future<void> setShaderChain(List<String> absolutePaths) async =>
      properties['glsl-shaders'] = absolutePaths.join(',');

  @override
  Future<String?> readProperty(String key) async => properties[key];

  @override
  Future<void> setProperty(String key, String value) async =>
      properties[key] = value;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _pos.close();
    await _dur.close();
    await _playing.close();
    await _buffering.close();
    await _err.close();
  }
}

void main() {
  late AppDatabase db;
  late FakeKernel kernel;

  const PlayerMedia media = PlayerMedia(
    id: 'ep_1',
    title: '测试片',
    url: 'http://127.0.0.1:8080/local/demo.mp4',
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    kernel = FakeKernel();
  });

  tearDown(() async {
    await db.close();
  });

  test('播放中每 5 秒写一次 history（走 record，增量由 DAO 算）', () async {
    // 断言"节拍"是 5 秒；跑测试时用 30ms 把它压快，逻辑完全一样
    expect(PlayerController.defaultPersistInterval,
        const Duration(seconds: 5));

    final PlayerController c = PlayerController(
      kernel: kernel,
      history: db.historyDao,
      persistInterval: const Duration(milliseconds: 30),
    );

    await c.open(media);
    kernel.emitDuration(const Duration(seconds: 600));
    kernel.emitPosition(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 45));

    History? h = await db.historyDao.byId(media.id);
    expect(h, isNotNull);
    expect(h!.position, 10);
    // 第一次写入只落位置，不凭首帧补计时
    expect(h.watchedSeconds, 0);

    // 再看 15 秒 → delta 15 被累加
    kernel.emitPosition(const Duration(seconds: 25));
    await Future<void>.delayed(const Duration(milliseconds: 45));

    h = await db.historyDao.byId(media.id);
    expect(h!.position, 25);
    expect(h.watchedSeconds, 15);

    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  test('暂停立刻落盘一次，不用等 5 秒', () async {
    final PlayerController c = PlayerController(
      kernel: kernel,
      history: db.historyDao,
      persistInterval: const Duration(minutes: 5),
    );
    await c.open(media);
    kernel.emitDuration(const Duration(seconds: 600));
    kernel.emitPosition(const Duration(seconds: 100));

    await c.pause();

    expect(kernel.pauseCalled, isTrue);
    final History? h = await db.historyDao.byId(media.id);
    expect(h!.position, 100);
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  test('续播：只有 (5, duration-10) 区间才从上次位置开始', () async {
    final PlayerController c = PlayerController(
      kernel: kernel,
      history: db.historyDao,
    );

    // 看过 30 秒 → 续播 30 秒
    await db.historyDao.record(
      id: 'a',
      title: 'a',
      url: 'u-a',
      sourceKind: 'local',
      position: 30,
      duration: 600,
    );
    expect(
      await c.resumeStart(const PlayerMedia(id: 'a', title: 'a', url: 'u')),
      const Duration(seconds: 30),
    );

    // 只看了 3 秒 → 视为没看过，从头
    await db.historyDao.record(
      id: 'b',
      title: 'b',
      url: 'u-b',
      sourceKind: 'local',
      position: 3,
      duration: 600,
    );
    expect(
      await c.resumeStart(const PlayerMedia(id: 'b', title: 'b', url: 'u')),
      Duration.zero,
    );

    // 595 秒（片尾 10 秒内）→ 算看完，从头
    await db.historyDao.record(
      id: 'c',
      title: 'c',
      url: 'u-c',
      sourceKind: 'local',
      position: 595,
      duration: 600,
    );
    expect(
      await c.resumeStart(const PlayerMedia(id: 'c', title: 'c', url: 'u')),
      Duration.zero,
    );

    // 没有历史 → 从头
    expect(
      await c.resumeStart(const PlayerMedia(id: 'zz', title: 'zz', url: 'u')),
      Duration.zero,
    );

    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  test('倍速夹在 0.25–4.0，并给内核打开 pitch correction', () async {
    final PlayerController c = PlayerController(
      kernel: kernel,
      history: db.historyDao,
    );
    await c.open(media);

    await c.setRate(9);
    expect(c.rate, 4.0);
    expect(kernel.rate, 4.0);

    await c.setRate(0.1);
    expect(c.rate, 0.25);
    expect(kernel.rate, 0.25);

    expect(kernel.properties['audio-pitch-correction'], 'yes');

    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
}
