import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// 同目录字幕扫描（F12）：只扫视频所在目录，**不递归**。
///
/// 认这些前缀：`promo.srt` / `promo.zh.srt` / `promo.zh-CN.ass` / `promo.简体.ass`
/// 语言认不出来就标 `und`，显示名用文件名。
class ScannedSubtitle {
  const ScannedSubtitle({
    required this.path,
    required this.lang,
    required this.label,
    required this.format,
  });

  final String path;
  final String lang;
  final String label;
  final String format;
}

class SubtitleScanner {
  const SubtitleScanner();

  static const Set<String> _exts = <String>{'srt', 'ass', 'ssa', 'vtt'};

  /// 语言关键字 → BCP-47（顺序有意义：繁体行必须排在简体行前面，
  /// 否则 `zh-TW` 会先被简体行的 `zh` 关键字命中，繁体字幕被标成简体）
  static const List<List<String>> _langTable = <List<String>>[
    <String>['zh-hant', 'zh-tw', 'zh_tw', '繁体', '繁中', 'cht'],
    <String>['zh-hans', 'zh-cn', 'zh_cn', '简体', '简中', 'chs', 'zh'],
    <String>['en', 'eng', '英文', '英语'],
    <String>['ja', 'jp', 'jpn', '日文', '日语'],
  ];

  static const Map<String, String> _langLabel = <String, String>{
    'zh': '简体中文',
    'zh-CN': '简体中文',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁体中文',
    'en': '英文',
    'ja': '日文',
    'und': '未标注语言',
  };

  static String labelOf(String lang) => _langLabel[lang] ?? lang;

  /// 从文件名（去掉扩展名后的剩余段）里认语言
  static String langOf(String stem) {
    final String low = stem.toLowerCase();
    for (final List<String> row in _langTable) {
      final String canon = row.first;
      for (int i = 1; i < row.length; i++) {
        final String k = row[i];
        if (low == k || low.endsWith('.$k') || low.contains('.$k.') ||
            low.endsWith('_$k') || low.endsWith('-$k') || low.contains(k)) {
          if (canon == 'zh-hans') return 'zh';
          if (canon == 'zh-hant') return 'zh-Hant';
          if (canon == 'en') return 'en';
          return 'ja';
        }
      }
    }
    return 'und';
  }

  /// 扫 `videoPath` 同目录里属于这条片子的字幕
  Future<List<ScannedSubtitle>> scan(String videoPath) async {
    final List<ScannedSubtitle> out = <ScannedSubtitle>[];
    if (videoPath.isEmpty) return out;
    final File vf = File(videoPath);
    final Directory dir = vf.parent;
    if (!dir.existsSync()) {
      debugLog('[YQK-SUB] scan miss dir=${dir.path}');
      return out;
    }
    final String vname = vf.uri.pathSegments.last;
    final int dot = vname.lastIndexOf('.');
    final String base = dot <= 0 ? vname : vname.substring(0, dot);

    final List<FileSystemEntity> entries = dir.listSync(followLinks: false);
    for (final FileSystemEntity e in entries) {
      if (e is! File) continue;
      final String name = e.uri.pathSegments.last;
      final int d = name.lastIndexOf('.');
      if (d <= 0) continue;
      final String ext = name.substring(d + 1).toLowerCase();
      if (!_exts.contains(ext)) continue;
      final String stem = name.substring(0, d);
      if (stem != base && !stem.startsWith('$base.')) continue;
      final String rest = stem == base ? '' : stem.substring(base.length + 1);
      final String lang = rest.isEmpty ? 'und' : langOf(rest);
      out.add(ScannedSubtitle(
        path: e.path,
        lang: lang,
        label: rest.isEmpty ? name : '${labelOf(lang)} · $name',
        format: ext,
      ));
    }
    debugLog('[YQK-SUB] scan dir=${dir.path} base=$base hit=${out.length} '
        'entries=${entries.length}');
    for (final ScannedSubtitle s in out) {
      debugLog('[YQK-SUB] scan item lang=${s.lang} fmt=${s.format} '
          'name=${s.path.split('/').last}');
    }
    return out;
  }

  /// 把 `file:///sdcard/x/y.mkv` 还原成本地绝对路径
  static String localPathOf(String url) {
    if (url.startsWith('file://')) {
      final Uri u = Uri.parse(url);
      return u.toFilePath();
    }
    return url;
  }

  static bool isLocal(String url) =>
      url.startsWith('file://') || url.startsWith('/');

  /// 从 media.url 推出「本地视频文件路径」；推不出返回 null。
  ///
  /// 本机媒体库给的是 `http://127.0.0.1:8080/local/media/play?path=<编码后的绝对路径>`，
  /// 这种也算本地片子（同一个文件，只是走了本地 HTTP 直出）。
  static String? videoPathOf(String url) {
    if (isLocal(url)) return localPathOf(url);
    if (!url.contains('/local/media/play')) return null;
    final Uri? u = Uri.tryParse(url);
    final String? p = u?.queryParameters['path'];
    if (p == null || p.isEmpty) return null;
    return p;
  }
}

/// 扫描器里用不到 Flutter，但日志要跟全项目一致走 debugPrint
void debugLog(String s) => debugPrint(s);
