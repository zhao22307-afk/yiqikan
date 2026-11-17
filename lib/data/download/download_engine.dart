import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_task.dart';
import '../../core/notify/notifier.dart';

/// F2 下载引擎：队列 + 最多 2 个并发 + 断点续传。
///
/// 用 dio（工程已有依赖）而**不是** http：pubspec 里没有 http 包，加依赖被禁止，
/// dio 的 `ResponseType.stream` 正好满足「拿 stream 写 RandomAccessFile」。
///
/// 续传靠 `Range: bytes=<received>-`：
///   206 → 接着写；200 → 服务器不认 Range，从头写；416 → 已经下完。
class DownloadEngine {
  DownloadEngine._();

  static final DownloadEngine instance = DownloadEngine._();

  /// 并发上限（任务书要求 2，不许开满）
  static const int maxConcurrent = 2;

  /// 每 64 KB 或 500 ms 更新一次进度，别每个包都通知 UI
  static const int _chunkBytes = 64 * 1024;
  static const int _tickMs = 500;

  static const String _prefsKey = 'yiqikan_download_queue';

  final ValueNotifier<List<DownloadTask>> tasks =
      ValueNotifier<List<DownloadTask>>(<DownloadTask>[]);

  final Dio _dio = Dio();
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  bool _ready = false;

  /// App 起来后调一次：把 prefs 里的队列读回来（queued / paused 继续挂着）
  Future<void> ensureReady() async {
    if (_ready) return;
    _ready = true;
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final List<DownloadTask> restored = DownloadTask.decodeList(
      sp.getString(_prefsKey),
    );
    if (restored.isEmpty) return;
    tasks.value = restored;
    debugPrint('[YQK-DL] restore n=${restored.length} '
        'paused=${restored.where((DownloadTask t) => t.state == DownloadState.paused).length}');
  }

  Future<DownloadTask?> byUrl(String url) async {
    await ensureReady();
    for (final DownloadTask t in tasks.value) {
      if (t.url == url) return t;
    }
    return null;
  }

  /// 入队。已经有一条同 url 且未失败/未删的任务时返回 false，UI 弹「已在下载队列」。
  /// 失败的任务允许重下一次（否则这条 url 会被一条坏记录永久卡住）。
  Future<bool> enqueue({required String url, required String title}) async {
    await ensureReady();
    final DownloadTask? old = await byUrl(url);
    if (old != null && old.state != DownloadState.failed) {
      debugPrint('[YQK-DL] dup url=$url');
      return false;
    }
    if (old != null) {
      // 失败的旧记录先清掉，占位 path 一样，接着用同一个 id
      await remove(old.id);
    }
    final Directory dir =
        Directory(p.join((await getApplicationSupportDirectory()).path, 'download'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final String id =
        md5.convert(utf8.encode(url)).toString().substring(0, 16);
    final String ext = _extOf(url);
    final DownloadTask t = DownloadTask(
      id: id,
      url: url,
      title: title,
      savePath: p.join(dir.path, '$id$ext'),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    tasks.value = <DownloadTask>[...tasks.value, t];
    debugPrint('[YQK-DL] start url=$url range=0 id=$id');
    await _save();
    _pump();
    return true;
  }

  void _pump() {
    int running = tasks.value
        .where((DownloadTask t) => t.state == DownloadState.running)
        .length;
    for (final DownloadTask t in tasks.value) {
      if (running >= maxConcurrent) break;
      if (t.state != DownloadState.queued) continue;
      running++;
      unawaited(_run(t));
    }
  }

  Future<void> _run(DownloadTask t) async {
    t.state = DownloadState.running;
    t.error = null;
    _emit();
    final CancelToken token = CancelToken();
    _tokens[t.id] = token;
    RandomAccessFile? raf;
    int written = 0;
    int lastEmitBytes = 0;
    int lastEmitAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final Response<ResponseBody> r = await _dio.get<ResponseBody>(
        t.url,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 30),
          headers: <String, String>{
            if (t.received > 0) 'range': 'bytes=${t.received}-',
          },
          validateStatus: (int? _) => true,
        ),
        cancelToken: token,
      );
      final int code = r.statusCode ?? 0;
      if (code == 416) {
        debugPrint('[YQK-DL] range=${t.received} code=416 already-done');
        t.state = DownloadState.done;
        if (t.total < 0) t.total = t.received;
        await _save();
        _emit();
        _pump();
        return;
      }
      final String len = r.headers.value('content-length') ?? '';
      final int partLen = int.tryParse(len) ?? -1;
      if (code == 206) {
        debugPrint('[YQK-DL] range=${t.received} code=206');
        if (t.total < 0 && partLen >= 0) t.total = t.received + partLen;
      } else {
        // 服务器不认 Range（或本来就没有），只能从头写
        debugPrint('[YQK-DL] range=${t.received} code=$code (no range support)');
        t.received = 0;
        if (partLen >= 0) t.total = partLen;
      }
      final Directory dir = Directory(p.dirname(t.savePath));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      raf = File(t.savePath).openSync(
        mode: t.received > 0 ? FileMode.append : FileMode.write,
      );
      final Stream<Uint8List> stream = r.data!.stream;
      await for (final Uint8List chunk in stream) {
        raf.writeFromSync(chunk);
        written += chunk.length;
        t.received += chunk.length;
        final int now = DateTime.now().millisecondsSinceEpoch;
        if (written - lastEmitBytes >= _chunkBytes || now - lastEmitAt >= _tickMs) {
          final int dt = now - lastEmitAt;
          if (dt > 0) {
            t.speedKbps = (written - lastEmitBytes) / 1024 / (dt / 1000);
          }
          lastEmitBytes = written;
          lastEmitAt = now;
          debugPrint('[YQK-DL] recv=${t.received}/${t.total}');
          _emit();
          await _saveThrottled();
        }
      }
      raf.closeSync();
      raf = null;
      t.state = DownloadState.done;
      t.speedKbps = 0;
      if (t.total < 0) t.total = t.received;
      debugPrint('[YQK-DL] done id=${t.id} size=${t.received}');
      await _save();
      _emit();
      // G9：下载完成通知（权限被拒时内部静默降级，不影响下载结果）
      unawaited(AppNotifier.instance.showDownloadDone(t.title, t.savePath));
    } on DioException catch (e) {
      raf?.closeSync();
      raf = null;
      if (CancelToken.isCancel(e)) {
        // pause / delete 主动取消：保留 received，状态由调用方设好
        debugPrint('[YQK-DL] cancel id=${t.id} at=${t.received}');
      } else {
        t.state = DownloadState.failed;
        t.error = '${e.type.name}: ${e.message ?? ''} / ${e.error ?? ''}';
        t.speedKbps = 0;
        debugPrint('[YQK-DL] fail id=${t.id} error=${t.error}');
        await _save();
      }
      _emit();
    } catch (e) {
      raf?.closeSync();
      raf = null;
      t.state = DownloadState.failed;
      t.error = '$e';
      t.speedKbps = 0;
      debugPrint('[YQK-DL] fail id=${t.id} error=$e');
      await _save();
      _emit();
    } finally {
      _tokens.remove(t.id);
      _pump();
    }
  }

  Future<void> pause(String id) async {
    final DownloadTask? t = _find(id);
    if (t == null) return;
    _tokens[id]?.cancel('paused');
    t.state = DownloadState.paused;
    t.speedKbps = 0;
    debugPrint('[YQK-DL] pause id=$id at=${t.received}');
    _emit();
    await _save();
  }

  Future<void> resume(String id) async {
    final DownloadTask? t = _find(id);
    if (t == null || t.state == DownloadState.done) return;
    t.state = DownloadState.queued;
    debugPrint('[YQK-DL] resume id=$id from=${t.received}');
    _emit();
    await _save();
    _pump();
  }

  /// 删任务 + 删文件
  Future<void> remove(String id) async {
    final DownloadTask? t = _find(id);
    if (t == null) return;
    _tokens[id]?.cancel('deleted');
    try {
      final File f = File(t.savePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 文件被播放器占着就下次再删，任务照样从列表里去掉
    }
    tasks.value = tasks.value.where((DownloadTask x) => x.id != id).toList();
    debugPrint('[YQK-DL] delete id=$id');
    _emit();
    await _save();
  }

  Future<void> pauseAll() async {
    for (final DownloadTask t in tasks.value.toList()) {
      if (t.state == DownloadState.running || t.state == DownloadState.queued) {
        await pause(t.id);
      }
    }
  }

  Future<void> resumeAll() async {
    for (final DownloadTask t in tasks.value.toList()) {
      if (t.state == DownloadState.paused || t.state == DownloadState.failed) {
        await resume(t.id);
      }
    }
  }

  Future<void> clearDone() async {
    final List<DownloadTask> keep = tasks.value
        .where((DownloadTask t) => t.state != DownloadState.done)
        .toList();
    final int drop = tasks.value.length - keep.length;
    tasks.value = keep;
    debugPrint('[YQK-DL] clear-done n=$drop');
    _emit();
    await _save();
  }

  DownloadTask? _find(String id) {
    for (final DownloadTask t in tasks.value) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _emit() {
    tasks.value = List<DownloadTask>.unmodifiable(tasks.value);
  }

  int _lastSaveAt = 0;

  Future<void> _saveThrottled() async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSaveAt < 1000) return;
    _lastSaveAt = now;
    await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, DownloadTask.encodeList(tasks.value));
    } catch (_) {
      // 存不进去不影响下载本身
    }
  }

  static String _extOf(String url) {
    final Uri? u = Uri.tryParse(url);
    final String last = u == null ? url : (u.pathSegments.isEmpty ? '' : u.pathSegments.last);
    final String ext = p.extension(last);
    if (ext.isEmpty || ext.length > 6) return '.mp4';
    return ext;
  }
}
