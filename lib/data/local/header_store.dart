import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';

/// 一条「按站点记忆的请求头」规则。
///
/// 本轮 10 号要求：用户可以加 / 删 / 改**任意**键值对，不限于 Referer；
/// 改完要能立刻重播验证，所以这里只负责存，重播由播放页触发。
class HeaderRule {
  HeaderRule({required this.host, required Map<String, String> headers})
      : headers = Map<String, String>.from(headers);

  /// 生效站点（空串表示所有站点）
  final String host;

  /// 键值对，键大小写原样保存（HTTP 头不区分大小写，但用户看得懂原样最好）
  final Map<String, String> headers;

  bool appliesTo(String url) {
    if (host.isEmpty) return true;
    final Uri? uri = Uri.tryParse(url);
    final String h = uri?.host.toLowerCase() ?? '';
    return h == host.toLowerCase() || h.endsWith('.${host.toLowerCase()}');
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'host': host,
        'headers': headers,
      };

  static HeaderRule fromJson(Map<String, Object?> json) {
    final Map<Object?, Object?> raw =
        (json['headers'] as Map<Object?, Object?>?) ?? <Object?, Object?>{};
    return HeaderRule(
      host: (json['host'] as String?) ?? '',
      headers: raw.map<String, String>(
        (Object? k, Object? v) => MapEntry<String, String>('$k', '$v'),
      ),
    );
  }

  HeaderRule copyWith({String? host, Map<String, String>? headers}) =>
      HeaderRule(host: host ?? this.host, headers: headers ?? this.headers);
}

/// 请求头规则的本地存储（只进 SharedPreferences，不联网、不上传）。
class HeaderStore {
  HeaderStore({SharedPreferences? prefs}) : _injected = prefs;

  static const String storageKey = '${kPrefsPrefix}header_rules';

  final SharedPreferences? _injected;
  SharedPreferences? _prefs;
  List<HeaderRule>? _cache;

  Future<SharedPreferences> _sp() async =>
      _prefs ??= _injected ?? await SharedPreferences.getInstance();

  Future<List<HeaderRule>> all() async {
    final List<HeaderRule>? cached = _cache;
    if (cached != null) return cached;
    final SharedPreferences sp = await _sp();
    final String? raw = sp.getString(storageKey);
    final List<HeaderRule> rules = <HeaderRule>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final Object? item in decoded) {
            if (item is Map) {
              rules.add(HeaderRule.fromJson(item.cast<String, Object?>()));
            }
          }
        }
      } on FormatException {
        // 存坏了就当没有，不放异常给 UI
      }
    }
    _cache = rules;
    return rules;
  }

  Future<void> _save(List<HeaderRule> rules) async {
    final SharedPreferences sp = await _sp();
    _cache = rules;
    await sp.setString(
      storageKey,
      jsonEncode(rules.map((HeaderRule r) => r.toJson()).toList()),
    );
  }

  /// 覆盖某个站点的整张表（编辑器保存时走这个：加 / 删 / 改一次落盘）
  Future<void> put(String host, Map<String, String> headers) async {
    final List<HeaderRule> rules = List<HeaderRule>.from(await all());
    final String key = host.toLowerCase();
    final int idx = rules.indexWhere(
      (HeaderRule r) => r.host.toLowerCase() == key,
    );
    final HeaderRule rule = HeaderRule(host: host, headers: headers);
    if (idx >= 0) {
      rules[idx] = rule;
    } else {
      rules.add(rule);
    }
    await _save(rules);
  }

  Future<void> remove(String host) async {
    final List<HeaderRule> rules = List<HeaderRule>.from(await all())
      ..removeWhere((HeaderRule r) => r.host.toLowerCase() == host.toLowerCase());
    await _save(rules);
  }

  /// 播放某个地址时该用的请求头：站点规则里命中的全部并进来（后者覆盖前者）
  Future<Map<String, String>> headersFor(
    String url, {
    Map<String, String> base = const <String, String>{},
  }) async {
    final Map<String, String> out = Map<String, String>.from(base);
    for (final HeaderRule r in await all()) {
      if (r.appliesTo(url)) out.addAll(r.headers);
    }
    return out;
  }
}
