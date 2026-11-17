import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 一条错误记录（G6 诊断页 + G7 崩溃日志共用）。
///
/// 只存「够定位」的三样：时间、类型、消息首行 + 栈；不存任何业务数据
/// （url 里的 token、房间密码这类东西即便出现也只会是异常消息的一部分，
/// 由调用方保证不把凭据塞进 message）。
class ErrorEntry {
  ErrorEntry({
    required this.at,
    required this.kind,
    required this.message,
    this.stack,
  });

  /// 毫秒时间戳（与 history.watchedAt 同一套口径）。
  final int at;

  /// `sync` / `async` / `build` / `net`。
  final String kind;

  /// 异常消息（可能多行）。
  final String message;

  /// 栈；可能为 null（比如网络错误只带 message）。
  final String? stack;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(at);

  /// 消息首行（列表只显示这一行）。
  String get firstLine => message.split('\n').first;

  /// `HH:mm:ss`，本地时区。
  String get clock {
    final DateTime t = time;
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// 导出文本里的时间：`yyyy-MM-dd HH:mm:ss`。
  String get stamp {
    final DateTime t = time;
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// 栈只留前 [lines] 行（导出时够用，又不至于把文件撑大）。
  String stackText([int lines = 30]) {
    final String? st = stack;
    if (st == null || st.isEmpty) return '';
    final List<String> all = st.split('\n');
    if (all.length <= lines) return st;
    return '${all.take(lines).join('\n')}\n… (${all.length - lines} more lines)';
  }
}

/// 错误环形缓存 + 落盘（G6 的地基，G7 复用）。
///
/// 三道约束：
/// 1. 内存里最多 [maxEntries] 条，先进先出，绝不无限长（异常风暴时也不涨内存）。
/// 2. 落盘节流 500ms 合并一次 —— 一连串异常只会写一次盘。
/// 3. 文件超过 [maxFileBytes] 只留后一半，避免把用户存储写满。
class ErrorLog {
  ErrorLog._();

  /// 内存里保留的条数上限。
  static const int maxEntries = 50;

  /// 落盘文件的大小上限（512 KB）。
  static const int maxFileBytes = 512 * 1024;

  /// 节流窗口：第一个 add 之后 500ms 才真正写盘。
  static const Duration flushDelay = Duration(milliseconds: 500);

  static final List<ErrorEntry> _buf = <ErrorEntry>[];

  static Timer? _timer;
  static bool _writing = false;
  static bool _dirty = false;

  /// 供测试/诊断读的全量（新→旧）。返回副本，外部改不到内部。
  static List<ErrorEntry> get all => List<ErrorEntry>.unmodifiable(_buf);

  /// 记一条。`kind` 取值见 [ErrorEntry.kind]；`e` 里的换行会被保留（栈单独给）。
  static void add(String kind, Object e, [StackTrace? st]) {
    final ErrorEntry entry = ErrorEntry(
      at: DateTime.now().millisecondsSinceEpoch,
      kind: kind,
      message: e.toString(),
      stack: st?.toString(),
    );
    _buf.add(entry);
    // 环形：多了丢最老的
    while (_buf.length > maxEntries) {
      _buf.removeAt(0);
    }
    debugPrint('[YQK-ERRLOG] add kind=$kind msg=${entry.firstLine}');
    unawaited(flushToDisk());
  }

  /// 最近 [n] 条（新→旧），诊断页直接用。
  static List<ErrorEntry> recent([int n = 20]) {
    if (n <= 0) return const <ErrorEntry>[];
    final int from = _buf.length > n ? _buf.length - n : 0;
    final List<ErrorEntry> tail = _buf.sublist(from);
    return tail.reversed.toList(growable: false);
  }

  /// 纯文本导出（诊断页「复制全部」用；不含 HTML/颜色，粘到哪儿都能看）。
  static String exportText() {
    final StringBuffer b = StringBuffer()
      ..writeln('# 一起看 错误日志')
      ..writeln('# 条数 ${_buf.length} / 上限 $maxEntries')
      ..writeln();
    for (final ErrorEntry e in recent(_buf.length)) {
      b.writeln('[${e.stamp}] ${e.kind} ${e.firstLine}');
      final String st = e.stackText();
      if (st.isNotEmpty) {
        for (final String line in st.split('\n')) {
          b.writeln('    $line');
        }
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  /// 落盘的绝对路径（`<support>/logs/crash.log`）。
  static Future<File> file() async {
    final Directory dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/logs',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/crash.log');
  }

  /// 节流写盘：500ms 内多次调用只写一次。
  ///
  /// 失败只打日志 —— 记错误的过程本身再抛错就没意义了。
  static Future<void> flushToDisk() async {
    _dirty = true;
    if (_writing) return;
    _timer ??= Timer(flushDelay, () {
      _timer = null;
      unawaited(_write());
    });
  }

  /// 立刻写一次（崩溃兜底页用：进程可能活不到 500ms 之后）。
  static Future<void> flushNow() async {
    _timer?.cancel();
    _timer = null;
    await _write();
  }

  static Future<void> _write() async {
    if (!_dirty || _writing) return;
    _writing = true;
    _dirty = false;
    try {
      final File f = await file();
      final StringBuffer b = StringBuffer();
      // 只写「上次之后新增」的：简单起见用时间戳游标（同毫秒的会重复，可接受）
      for (final ErrorEntry e in _buf) {
        if (e.at < _lastWrittenAt) continue;
        b.writeln('${e.stamp}|${e.kind}|${e.firstLine}');
        final String st = e.stackText();
        if (st.isNotEmpty) {
          for (final String line in st.split('\n')) {
            b.writeln('    $line');
          }
        }
      }
      if (b.isEmpty) {
        _lastWrittenAt = DateTime.now().millisecondsSinceEpoch;
        return;
      }
      await f.writeAsString(b.toString(), mode: FileMode.append, flush: true);
      _lastWrittenAt = DateTime.now().millisecondsSinceEpoch;
      await _truncateIfBig(f);
      debugPrint('[YQK-ERRLOG] flush size=${f.lengthSync()}');
    } on Object catch (e) {
      debugPrint('[YQK-ERRLOG] flush fail: $e');
    } finally {
      _writing = false;
      if (_dirty) {
        // 写的时候又来了新错误：再排一次
        _timer ??= Timer(flushDelay, () {
          _timer = null;
          unawaited(_write());
        });
      }
    }
  }

  /// 超过 [maxFileBytes] 只留后一半（整行可能被切断，阅读时可接受）。
  static Future<void> _truncateIfBig(File f) async {
    try {
      final int len = f.lengthSync();
      if (len <= maxFileBytes) return;
      final List<int> bytes = await f.readAsBytes();
      final List<int> tail = bytes.sublist(len ~/ 2);
      await f.writeAsBytes(tail, flush: true);
      debugPrint('[YQK-ERRLOG] truncate $len -> ${tail.length}');
    } on Object catch (e) {
      debugPrint('[YQK-ERRLOG] truncate fail: $e');
    }
  }

  static int _lastWrittenAt = 0;

  /// 清空内存缓存（诊断页「清空」）。
  ///
  /// 不动已落盘的文件 —— 那是崩溃证据，清理走「导出日志」旁边的说明，
  /// 由 [clearFile] 单独执行。
  static void clear() {
    _buf.clear();
    _lastWrittenAt = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[YQK-ERRLOG] clear');
  }

  /// 删掉落盘文件（验收清理 / 用户手动清）。
  static Future<bool> clearFile() async {
    try {
      final File f = await file();
      if (f.existsSync()) {
        await f.delete();
        debugPrint('[YQK-ERRLOG] file deleted');
        return true;
      }
      return true;
    } on Object catch (e) {
      debugPrint('[YQK-ERRLOG] file delete fail: $e');
      return false;
    }
  }

  /// 测试用：把内部状态复位（不影响文件）。
  @visibleForTesting
  static void resetForTest() {
    _buf.clear();
    _timer?.cancel();
    _timer = null;
    _writing = false;
    _dirty = false;
    _lastWrittenAt = 0;
  }
}
