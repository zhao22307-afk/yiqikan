import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/domain/translator.dart';

/// 只用来喂固定响应的假适配器，不走网络。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.status = 200});

  final String body;
  final int status;
  int calls = 0;
  String? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    lastBody = '${options.data}';
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('NoopTranslator 恒返回 null 且 isConfigured=false', () async {
    const NoopTranslator t = NoopTranslator();
    expect(t.isConfigured, isFalse);
    expect(await t.translate('hello'), isNull);
  });

  test('HttpTranslator 解析 translated 字段', () async {
    final Dio dio = Dio();
    final _FakeAdapter ad =
        _FakeAdapter('{"translated":"你好"}')..calls = 0;
    dio.httpClientAdapter = ad;
    final HttpTranslator t =
        HttpTranslator(endpoint: 'https://x/translate', key: 'k', dio: dio);
    expect(t.isConfigured, isTrue);
    expect(await t.translate('hello'), '你好');
    expect(ad.calls, 1);
    expect(ad.lastBody, contains('hello'));
  });

  test('HttpTranslator 兼容 translation / data.translations 两种形状', () async {
    final Dio dio = Dio();
    dio.httpClientAdapter = _FakeAdapter('{"translation":"早上好"}');
    expect(
      await HttpTranslator(endpoint: 'https://x/t', dio: dio).translate('hi'),
      '早上好',
    );

    final Dio dio2 = Dio();
    dio2.httpClientAdapter = _FakeAdapter(
        '{"translations":[{"translated":"晚上好"}]}');
    expect(
      await HttpTranslator(endpoint: 'https://x/t', dio: dio2).translate('hi'),
      '晚上好',
    );
  });

  test('HttpTranslator 错误路径：4xx / 空响应都返回 null', () async {
    final Dio dio = Dio();
    dio.httpClientAdapter = _FakeAdapter('{"detail":"bad"}', status: 400);
    expect(
      await HttpTranslator(endpoint: 'https://x/t', dio: dio).translate('hi'),
      isNull,
    );

    final Dio dio2 = Dio();
    dio2.httpClientAdapter = _FakeAdapter('{}');
    expect(
      await HttpTranslator(endpoint: 'https://x/t', dio: dio2).translate('hi'),
      isNull,
    );
  });

  test('空端点时 isConfigured=false 且不发请求', () async {
    final Dio dio = Dio();
    final _FakeAdapter ad = _FakeAdapter('{"translated":"x"}');
    dio.httpClientAdapter = ad;
    final HttpTranslator t = HttpTranslator(endpoint: '  ', dio: dio);
    expect(t.isConfigured, isFalse);
    expect(await t.translate('hi'), isNull);
    expect(ad.calls, 0);
  });
}
