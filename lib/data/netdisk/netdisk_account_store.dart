/// 网盘账号的「库里存什么 / 密室里存什么」分层（03 §5）。
///
/// - Drift `accounts` 表：只放能给用户看的东西（kind / 备注名 / 端点 / 账号名 / 状态）
/// - SecureStore：密码、token、cookie，key = `cred_<accountId>`
///
/// 这层负责把两边拼起来，按 kind 造出对应的 [NetdiskAdapter]。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;


import '../../core/constants.dart';
import '../../core/errors/app_exception.dart';
import '../db/app_database.dart';
import '../local/secure_store.dart';
import 'alist_adapter.dart';
import 'emby_adapter.dart';
import 'netdisk_adapter.dart';
import 'pan123_adapter.dart';
import 'quark_adapter.dart';
import 'share_link.dart';
import 'tianyi_adapter.dart';
import 'x115_adapter.dart';
import 'webdav_adapter.dart';

/// 添加账号时用户填的东西（敏感字段单独放，绝不进 Drift）
class NetdiskDraft {
  const NetdiskDraft({
    required this.kind,
    required this.displayName,
    required this.endpoint,
    this.username = '',
    this.password = '',
    this.token = '',
  });

  final NetdiskKind kind;
  final String displayName;
  final String endpoint;
  final String username;
  final String password;

  /// AList 的 token，或以后网盘的 cookie 串
  final String token;

  Map<String, String> get secret => <String, String>{
        if (username.isNotEmpty) 'username': username,
        if (password.isNotEmpty) 'password': password,
        if (token.isNotEmpty) 'token': token,
      };

  /// 非敏感字段（进 accounts.extra）
  Map<String, String> get publicExtra => <String, String>{
        'endpoint': endpoint,
      };
}

class NetdiskAccountStore {
  NetdiskAccountStore({required this.db, required this.secure});

  final AppDatabase db;
  final SecureStore secure;

  AccountDao get _dao => db.accountDao;

  /// 列表只查网盘类账号（B 站之类的账号走别的页面）
  Future<List<Account>> list() async {
    final List<Account> all = await _dao.all();
    const Set<String> kinds = <String>{
      'webdav',
      'alist',
      'emby',
      'quark',
      'pan115',
      'pan123',
      'tianyi',
    };
    return all.where((Account a) => kinds.contains(a.kind)).toList();
  }

  static String endpointOf(Account a) {
    final String? raw = a.extra;
    if (raw == null || raw.isEmpty) return '';
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return '${decoded['endpoint'] ?? ''}';
    } catch (_) {
      // 坏 JSON 就当没有端点
    }
    return '';
  }

  /// 新增账号：先验证再落库（验证失败不写入，避免留下坏账号）
  Future<Account> add(NetdiskDraft draft) async {
    final String id = 'acc_${DateTime.now().millisecondsSinceEpoch}';
    final NetdiskAdapter probe = _build(
      id: id,
      kind: draft.kind,
      endpoint: draft.endpoint,
      username: draft.username,
      password: draft.password,
      token: draft.token,
    );
    await probe.verify();

    // 表里存的是毫秒时间戳（tables.dart 用 IntColumn），不是 DateTime
    final int now = DateTime.now().millisecondsSinceEpoch;

    // 验证通过才写凭据 + 落库
    await secure.put('cred_$id', jsonEncode(draft.secret));
    final Account row = Account(
      id: id,
      kind: draft.kind.prefValue,
      displayName: draft.displayName.trim().isEmpty
          ? draft.kind.label
          : draft.displayName.trim(),
      username: draft.username.isEmpty ? null : draft.username,
      extra: jsonEncode(draft.publicExtra),
      status: 'ok',
      lastVerified: now,
      createdAt: now,
    );
    await _dao.upsert(row);
    return row;
  }

  Future<void> remove(Account a) async {
    await secure.delete('cred_${a.id}');
    await _dao.deleteById(a.id);
  }

  /// 重新验证并把状态写回（过期的显示「已过期」，点击可去重新登录）
  /// 把一条分享链接绑到账号上（写进 accounts.extra，不碰 SecureStore）
  Future<Account> bindShare(Account a, ShareLink link) async {
    final Map<String, Object?> extra = <String, Object?>{};
    final String? raw = a.extra;
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) extra.addAll(decoded.cast<String, Object?>());
      } on Object {
        // 坏 JSON 直接重建，别让绑定失败
      }
    }
    extra.addAll(link.toExtra());
    final Account next = a.copyWith(extra: Value<String>(jsonEncode(extra)));
    await _dao.upsert(next);
    return next;
  }

  /// 已绑定的分享（没绑过就是 null）
  static ShareLink? bindingOf(Account a) {
    final String? raw = a.extra;
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, Object?> m = decoded.cast<String, Object?>();
      String pick(String k) => '${m[k] ?? ''}';
      final NetdiskKind kind = NetdiskKind.parse(a.kind);
      switch (kind) {
        case NetdiskKind.quark:
          final String id = pick('pwd_id');
          return id.isEmpty
              ? null
              : ShareLink(kind: kind, shareId: id, receiveCode: pick('passcode'));
        case NetdiskKind.pan115:
          final String id = pick('share_code');
          return id.isEmpty
              ? null
              : ShareLink(kind: kind, shareId: id, receiveCode: pick('receive_code'));
        case NetdiskKind.pan123:
          final String id = pick('share_key');
          return id.isEmpty
              ? null
              : ShareLink(kind: kind, shareId: id, receiveCode: pick('share_pwd'));
        case NetdiskKind.tianyi:
          final String id = pick('shareId');
          return id.isEmpty
              ? null
              : ShareLink(kind: kind, shareId: id, receiveCode: pick('accessCode'));
        default:
          return null;
      }
    } on Object {
      return null;
    }
  }

  Future<bool> revalidate(Account a) async {
    try {
      final NetdiskAdapter adapter = await adapterFor(a);
      final bool ok = await adapter.verify();
      await _dao.setStatus(a.id, ok ? 'ok' : 'unknown');
      return ok;
    } on AuthExpiredException {
      await _dao.setStatus(a.id, 'expired');
      return false;
    } on AppException {
      await _dao.setStatus(a.id, 'invalid');
      return false;
    }
  }

  /// 用已存的凭据造适配器
  Future<NetdiskAdapter> adapterFor(Account a) async {
    final String? raw = await secure.get('cred_${a.id}');
    Map<String, dynamic> sec = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) sec = decoded.cast<String, dynamic>();
      } catch (_) {
        // 密室里的东西坏了 → 当作没登录
      }
    }
    return _build(
      id: a.id,
      kind: NetdiskKind.parse(a.kind),
      endpoint: endpointOf(a),
      username: '${sec['username'] ?? a.username ?? ''}',
      password: '${sec['password'] ?? ''}',
      token: '${sec['token'] ?? ''}',
      displayName: a.displayName,
    );
  }

  NetdiskAdapter _build({
    required String id,
    required NetdiskKind kind,
    required String endpoint,
    required String username,
    required String password,
    required String token,
    String? displayName,
  }) {
    final NetdiskAccountInfo info = NetdiskAccountInfo(
      kind: kind,
      displayName: displayName ?? kind.label,
      endpoint: endpoint,
    );
    switch (kind) {
      case NetdiskKind.webdav:
        return WebDavAdapter(
          account: info,
          username: username,
          password: password,
          store: secure,
        );
      case NetdiskKind.alist:
        return AlistAdapter(account: info, token: token, store: secure);
      case NetdiskKind.emby:
        return EmbyAdapter(
          account: info,
          username: username,
          password: password,
          store: secure,
        );
      case NetdiskKind.quark:
        return QuarkAdapter(account: info, cookie: token, store: secure);
      case NetdiskKind.pan115:
        return X115Adapter(account: info, cookie: token, store: secure);
      case NetdiskKind.pan123:
        return Pan123Adapter(account: info, token: token, store: secure);
      case NetdiskKind.tianyi:
        return TianyiAdapter(account: info, cookie: token, store: secure);
    }
  }

  /// UI 用：这家现在能不能加。第二段四家骨架都已接上，
  /// 只差真实凭据到手后把 verify 里的判定确认一遍。
  static bool canAddNow(NetdiskKind kind) => true;

  static String statusText(Account a) {
    switch (a.status) {
      case 'ok':
        return '正常';
      case 'expired':
        return '登录过期';
      case 'invalid':
        return '连不上';
      default:
        return '还没验证';
    }
  }

  static const String kindLabelFallback = kAppName;
}
