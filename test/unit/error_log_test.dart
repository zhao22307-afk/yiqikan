import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/core/error/error_log.dart';

void main() {
  setUp(ErrorLog.resetForTest);
  tearDown(ErrorLog.resetForTest);

  test('add 之后 recent 是新的在前，且带 kind / 首行', () {
    ErrorLog.add('sync', StateError('第一条'));
    ErrorLog.add('async', Exception('第二条\n第二行'));
    final List<ErrorEntry> r = ErrorLog.recent(10);
    expect(r.length, 2);
    expect(r.first.kind, 'async');
    expect(r.first.firstLine, 'Exception: 第二条');
    expect(r.last.kind, 'sync');
    expect(r.last.firstLine, 'Bad state: 第一条');
  });

  test('环形缓存超过上限会丢最老的', () {
    for (int i = 0; i < ErrorLog.maxEntries + 7; i++) {
      ErrorLog.add('net', 'e$i');
    }
    expect(ErrorLog.all.length, ErrorLog.maxEntries);
    expect(ErrorLog.all.first.firstLine, 'e7'); // 前 7 条被挤掉
    expect(ErrorLog.recent(1).single.firstLine, 'e${ErrorLog.maxEntries + 6}');
  });

  test('recent(n) 只给最后 n 条，顺序新→旧', () {
    for (int i = 0; i < 5; i++) {
      ErrorLog.add('build', 'x$i');
    }
    final List<ErrorEntry> two = ErrorLog.recent(2);
    expect(two.map((ErrorEntry e) => e.firstLine).toList(), <String>['x4', 'x3']);
  });

  test('exportText 含表头、kind 与栈缩进', () {
    final StackTrace st = StackTrace.fromString('#0 main (file:///a.dart:1:1)\n#1 run');
    ErrorLog.add('build', StateError('炸了'), st);
    final String text = ErrorLog.exportText();
    expect(text, contains('# 一起看 错误日志'));
    expect(text, contains('build Bad state: 炸了'));
    expect(text, contains('    #0 main'));
  });

  test('栈超过 30 行会截断并注明剩余行数', () {
    final String long = List<String>.generate(40, (int i) => '#$i frame').join('\n');
    final ErrorEntry e = ErrorEntry(
      at: DateTime.now().millisecondsSinceEpoch,
      kind: 'sync',
      message: 'm',
      stack: long,
    );
    final String t = e.stackText();
    expect(t, contains('#29 frame'));
    expect(t, contains('10 more lines'));
    expect(t, isNot(contains('#30 frame')));
  });

  test('clear 后 recent 为空（不动文件）', () {
    ErrorLog.add('net', 'x');
    ErrorLog.clear();
    expect(ErrorLog.all, isEmpty);
    expect(ErrorLog.recent(5), isEmpty);
  });
}
