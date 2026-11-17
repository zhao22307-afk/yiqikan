/// H2 翻译服务的配置存取：端点进 prefs，密钥进 SecureStore。
///
/// 单独放一个文件的原因：设置页要写、播放页要读，两边都不该各写一份
/// 键名逻辑（写歪一个字符就变成「保存了但读不到」）。
library;

import '../../data/local/prefs.dart';
import '../../data/local/secure_store.dart';
import '../../domain/translator.dart';

class TranslatorStore {
  TranslatorStore({Prefs? prefs, SecureStore? secure})
      : _prefs = prefs,
        _secure = secure ?? SecureStore();

  static const String keySecret = 'translate_key';

  final Prefs? _prefs;
  final SecureStore _secure;

  Future<Prefs> _p() async => _prefs ?? await Prefs.open();

  /// 读端点（没配返回空串）
  Future<String> endpoint() async =>
      ((await _p()).getString(PrefKeys.translateEndpoint) ?? '').trim();

  /// 读密钥（没配返回空串）
  Future<String> secret() async =>
      (await _secure.get(keySecret) ?? '').trim();

  /// 组装出当前可用的翻译器。端点为空 → NoopTranslator（菜单里不显示「翻译」）。
  Future<Translator> load() async {
    final String ep = await endpoint();
    if (ep.isEmpty) return const NoopTranslator();
    final String sk = await secret();
    return HttpTranslator(endpoint: ep, key: sk);
  }

  /// 保存配置。`key` 传空串表示清掉密钥。
  Future<void> save({required String endpoint, required String key}) async {
    await (await _p())
        .setString(PrefKeys.translateEndpoint, endpoint.trim());
    if (key.trim().isEmpty) {
      await _secure.delete(keySecret);
    } else {
      await _secure.put(keySecret, key.trim());
    }
  }

  /// 清空（X-V4 复原用）
  Future<void> clear() async {
    await (await _p()).setString(PrefKeys.translateEndpoint, '');
    await _secure.delete(keySecret);
  }
}
