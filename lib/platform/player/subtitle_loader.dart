import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';

/// 字幕文件准备（15 §A5）。
///
/// mpv 只认 UTF-8 的字幕文件，网上一堆 SRT 是 GBK/GB18030 编码，
/// 直接 sub-add 出来全是乱码。所以流程固定为：
///   取字节 → 判编码 → GBK 转 UTF-8 → 落到缓存目录 → 把本地路径交给内核。
///
/// 为什么 GBK 解码走平台通道：Dart 只内置 utf8/latin1/ascii，
/// GBK 需要 7000+ 字符的映射表；Android 的 Charset 自带 GBK/GB18030，
/// 一个 MethodChannel 调用就够（见 MainActivity 的 charset 通道）。
class SubtitleLoader {
  SubtitleLoader({Dio? dio, this.channel = _defaultChannel})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: kHttpConnectTimeout,
                receiveTimeout: kHttpReadTimeout,
                // 字幕站点经常不认默认 UA
                headers: <String, String>{
                  'User-Agent': 'Mozilla/5.0 (Linux; Android 14) 一起看/1.0.0',
                },
              ),
            );

  static const MethodChannel _defaultChannel =
      MethodChannel('top.yiqikan/charset');

  final Dio _dio;
  final MethodChannel channel;

  /// 把「本地路径 / file:// / http(s) 地址」统一变成「本地 UTF-8 文件路径」。
  ///
  /// 已经是 UTF-8 的本地文件会原样返回，不重复落盘。
  Future<String> prepare(String source) async {
    final String? localPath = _localPathOf(source);

    if (localPath != null && await File(localPath).exists()) {
      final Uint8List bytes = await File(localPath).readAsBytes();
      if (_isUtf8(bytes)) return localPath;
      return _writeUtf8(await _toUtf8(bytes), localPath);
    }

    // 网络字幕：03 §11 的超时（8s 连接 / 20s 读取）在这里生效
    final Response<List<int>> resp = await _dio.get<List<int>>(
      source,
      options: Options(responseType: ResponseType.bytes),
    );
    final Uint8List bytes = Uint8List.fromList(resp.data ?? <int>[]);
    final Uint8List utf8Bytes =
        _isUtf8(bytes) ? bytes : await _toUtf8(bytes);
    return _writeUtf8(utf8Bytes, null);
  }

  /// 从 URL/URI 里取出本地路径；不是本地文件返回 null
  static String? _localPathOf(String source) {
    if (source.startsWith('file://')) {
      return Uri.parse(source).toFilePath();
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return null;
    }
    return source;
  }

  bool _isUtf8(Uint8List bytes) {
    try {
      utf8.decode(bytes);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// GBK/GB18030 → UTF-8（走平台通道，失败则原样返回并让 mpv 试一次）
  Future<Uint8List> _toUtf8(Uint8List bytes) async {
    try {
      final String? text = await channel.invokeMethod<String>(
        'decodeGbk',
        bytes,
      );
      if (text != null) return Uint8List.fromList(utf8.encode(text));
    } on PlatformException {
      // 通道不可用（比如在桌面/测试环境跑）：退回 latin1，至少不炸
    } on MissingPluginException {
      // 同上
    }
    return Uint8List.fromList(utf8.encode(latin1.decode(bytes)));
  }

  /// 写到缓存目录下的 subs/，文件名用内容 md5，重复字幕不重复写
  Future<String> _writeUtf8(Uint8List bytes, String? originalPath) async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(base.path, 'subs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final String hash = md5.convert(bytes).toString();
    final String ext = _extOf(originalPath) ?? '.srt';
    final File out = File(p.join(dir.path, 'sub_$hash$ext'));
    if (!await out.exists()) {
      await out.writeAsBytes(bytes, flush: true);
    }
    return out.path;
  }

  static String? _extOf(String? path) {
    if (path == null) return null;
    final String ext = p.extension(path).toLowerCase();
    const List<String> allowed = <String>['.srt', '.ass', '.ssa', '.vtt'];
    return allowed.contains(ext) ? ext : null;
  }
}
