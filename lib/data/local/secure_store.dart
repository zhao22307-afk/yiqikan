import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 凭据存放处（03 §5）。
///
/// 铁律：**凭据绝不进 SharedPreferences**。这张表之外的任何地方都不许出现
/// cookie/token/password 明文，本类是全项目唯一出口。
///
/// 版本说明：flutter_secure_storage 11.x 已把 `encryptedSharedPreferences`
/// 开关删掉——现在默认就是 KeyStore 保护的 AES-GCM + RSA-OAEP 密钥包装
/// （构造器签名里的 keyCipherAlgorithm / storageCipherAlgorithm），
/// 比旧的 EncryptedSharedPreferences 更强，所以这里用默认构造。
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                // Android: AES-GCM(数据) + RSA-OAEP-256(密钥)，密钥在 KeyStore 里
                resetOnError: true,
                migrateOnAlgorithmChange: true,
              ),
            );

  final FlutterSecureStorage _storage;

  /// 某些定制 ROM 的 Keystore 会直接抛异常（03 §5 的坑）。
  /// 打不开时降级为"进程内内存存储"：能用、能退回，但**绝不落盘**——
  /// 宁可这次不记住凭据，也不把 cookie 写进 SharedPreferences。
  final Map<String, String> _memoryFallback = <String, String>{};
  bool _degraded = false;

  /// 当前是否处于降级（内存）模式，便于诊断页显示
  bool get isDegraded => _degraded;

  Future<T> _guard<T>(Future<T> Function() op, T Function() onFailure) async {
    try {
      return await op();
    } on PlatformException catch (e) {
      _degrade('PlatformException: ${e.code}');
      return onFailure();
    } catch (e) {
      _degrade('$e');
      return onFailure();
    }
  }

  void _degrade(String reason) {
    if (_degraded) return;
    _degraded = true;
    // 只记原因，不记任何键值内容（凭据不落日志）
    developer.log('SecureStore 降级为内存模式：$reason', name: 'SecureStore');
  }

  Future<String?> get(String key) {
    return _guard<String?>(
      () => _storage.read(key: key),
      () => _memoryFallback[key],
    );
  }

  Future<void> put(String key, String value) {
    return _guard<void>(
      () => _storage.write(key: key, value: value),
      () => _memoryFallback[key] = value,
    );
  }

  Future<void> delete(String key) {
    return _guard<void>(
      () => _storage.delete(key: key),
      () => _memoryFallback.remove(key),
    );
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final String? raw = await get(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      // 内容坏了就当没有，不把坏数据抛给上层
      return null;
    }
  }

  Future<void> putJson(String key, Map<String, dynamic> value) {
    return put(key, jsonEncode(value));
  }

  /// 清空所有凭据（"退出全部账号"用）
  Future<void> clearAll() {
    return _guard<void>(
      () => _storage.deleteAll(),
      () => _memoryFallback.clear(),
    );
  }
}

/// 凭据键规范（03 §5）——键名一个都不许改，改了等于把老用户的凭据全丢掉。
class SecureKeys {
  const SecureKeys._();

  /// 账号凭据：JSON 字符串
  ///  quark  -> {"cookie": "..."}
  ///  pan115 -> {"cookie": "..."}
  ///  pan123 -> {"token": "...", "privateKey": "..."}
  ///  tianyi -> {"cookie": "...", "accessToken": "...", "expiresAt": 123}
  ///  emby   -> {"serverUrl": "...", "token": "...", "userId": "...", "deviceId": "..."}
  ///  webdav -> {"baseUrl": "...", "username": "...", "password": "..."}
  ///  alist  -> {"baseUrl": "...", "token": "..."}
  static String account(String id) => 'cred_$id';

  /// 片源密码（与 sources 表的 id 对应）
  static String sourcePwd(String id) => 'source_pwd_$id';

  /// 房间口令（自己开的房，下次自动填）
  static String roomPwd(String roomId) => 'room_pwd_$roomId';

  /// AI 服务 token（可选，用户自己配）
  static const String aiToken = 'ai_token';
}
