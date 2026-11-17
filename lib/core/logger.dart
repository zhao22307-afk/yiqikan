import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 环形日志缓冲（15 §A11：只留最近 500 行，给高级面板与导出用）。
///
/// 为什么要拦 debugPrint：media_kit / fvp 的日志最终都走 debugPrint，
/// 统一在这里收口，比在十几处调用点各写一遍可靠。
class AppLog {
  AppLog._();

  static const int maxLines = 500;

  static final Queue<String> _lines = Queue<String>();
  static bool _installed = false;

  /// 在 main() 里调一次即可；重复调是安全的。
  static void install() {
    if (_installed) return;
    _installed = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      debugPrintSynchronously(message, wrapWidth: wrapWidth);
    };
  }

  static void add(String line) {
    if (line.isEmpty) return;
    _lines.addLast(line);
    while (_lines.length > maxLines) {
      _lines.removeFirst();
    }
  }

  /// 最近 [count] 行，按时间顺序。
  static List<String> tail([int count = maxLines]) {
    if (count >= _lines.length) return List<String>.of(_lines);
    return _lines.skip(_lines.length - count).toList();
  }

  static void clear() => _lines.clear();
}
