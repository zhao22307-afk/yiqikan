/// H2 实时翻译：只做「发一句话、拿回一句译文」这一层。
///
/// 刻意不内置任何厂商 URL / API Key —— 用户自己在设置里填 endpoint。
/// 这样发布出去的包里没有可被扫出来的密钥，也方便换服务。
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// 翻译器接口。`null` 表示「翻不了」（没配置 / 服务报错），调用方据此决定提示文案。
abstract class Translator {
  Future<String?> translate(String text, {String to = 'zh'});

  /// 是否真的能翻（NoopTranslator 恒 false，用来决定菜单里显不显示「翻译」）
  bool get isConfigured;

  String get label;
}

/// 默认实现：什么都不做。没配翻译服务时用它，调用方据此隐藏入口。
class NoopTranslator implements Translator {
  const NoopTranslator();

  @override
  Future<String?> translate(String text, {String to = 'zh'}) async => null;

  @override
  bool get isConfigured => false;

  @override
  String get label => '未配置';
}

/// 用户自填的 HTTP 端点。约定：
/// - POST `endpoint`，JSON body `{"q": "<原文>", "target": "zh"}`
/// - 响应 JSON 里读 `translated`；也兼容 `translation` / `result` 三种常见字段名
class HttpTranslator implements Translator {
  HttpTranslator({
    required this.endpoint,
    this.key = '',
    Dio? dio,
    this.timeout = const Duration(seconds: 8),
  }) : _dio = dio ?? Dio();

  final String endpoint;

  /// 用户自己填的密钥；空表示服务不收密钥
  final String key;
  final Duration timeout;
  final Dio _dio;

  @override
  bool get isConfigured => endpoint.trim().isNotEmpty;

  @override
  String get label => isConfigured ? endpoint : '未配置';

  @override
  Future<String?> translate(String text, {String to = 'zh'}) async {
    final String q = text.trim();
    if (q.isEmpty || !isConfigured) return null;
    try {
      final Response<dynamic> res = await _dio.post<dynamic>(
        endpoint.trim(),
        data: <String, Object?>{'q': q, 'target': to},
        options: Options(
          headers: <String, Object?>{
            'Content-Type': 'application/json',
            if (key.trim().isNotEmpty) 'Authorization': 'Bearer ${key.trim()}',
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (int? _) => true,
        ),
      );
      if (res.statusCode == null || res.statusCode! >= 400) {
        return null;
      }
      final Object? data = res.data;
      if (data is Map) {
        for (final String k in <String>['translated', 'translation', 'result']) {
          final Object? v = data[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        // 有些服务把结果塞在 data.translations[0].translated
        final Object? arr = data['translations'];
        if (arr is List && arr.isNotEmpty && arr.first is Map) {
          final Object? v = (arr.first as Map)['translated'];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }
      if (data is String && data.trim().isNotEmpty) return data.trim();
      return null;
    } on Object {
      // 网络断了/超时都按「翻不了」处理，界面给一句人话就行
      return null;
    }
  }

  /// 设置页「测试」按钮用：发一句 hello，返回 null 就是通道不通。
  Future<String?> selfTest() => translate('hello', to: 'zh');
}
