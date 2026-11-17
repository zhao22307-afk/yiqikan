/// E9 relay 的客户端侧纯逻辑（网络那半边在服务端 `Relay.java`）。
///
/// 这里只放三件可单测的事：
///   1. `/local/relay` 的响应解析（configured / connected / lastError）
///   2. 重连退避：1s / 2s / 4s，最多 3 次，之后不再自增
///   3. 「未配置」与「配了但连不上」两种状态的区分
///
/// 真连中继要有 VPS，本轮只做骨架。
library;

/// `/local/relay` 的一份状态快照。
class RelayStatus {
  const RelayStatus({
    required this.configured,
    required this.connected,
    required this.url,
    required this.lastError,
    this.attempts = 0,
  });

  factory RelayStatus.fromJson(Object? raw) {
    if (raw is! Map) {
      return const RelayStatus(
        configured: false,
        connected: false,
        url: '',
        lastError: '',
      );
    }
    String s(Object? v) => v is String ? v : '';
    bool b(Object? v) => v == true;
    final Object? a = raw['attempts'];
    return RelayStatus(
      configured: b(raw['configured']),
      connected: b(raw['connected']),
      url: s(raw['url']),
      lastError: s(raw['lastError']),
      attempts: a is int ? a : (int.tryParse('${a ?? ''}') ?? 0),
    );
  }

  static const RelayStatus unconfigured = RelayStatus(
    configured: false,
    connected: false,
    url: '',
    lastError: '未配置中继',
  );

  final bool configured;
  final bool connected;
  final String url;
  final String lastError;
  final int attempts;

  /// 配了但没连上、且有错误 —— UI 该显示「中继连不上：xxx」。
  bool get failed => configured && !connected && lastError.isNotEmpty;

  @override
  String toString() =>
      'RelayStatus(configured=$configured, connected=$connected, url=$url, '
      'lastError=$lastError, attempts=$attempts)';
}

/// 重连退避（和服务端 `Relay.java` 的 1s/2s/4s、最多 3 次保持一致）。
class RelayBackoff {
  static const int maxAttempts = 3;
  static const List<int> delaysMs = <int>[1000, 2000, 4000];

  int _attempts = 0;

  int get attempts => _attempts;

  bool get exhausted => _attempts >= maxAttempts;

  /// 下一次重连前要等多久；已经到上限返回 null（不许无限重连）。
  int? nextDelay() {
    if (exhausted) return null;
    final int d = delaysMs[_attempts];
    _attempts++;
    return d;
  }

  void reset() {
    _attempts = 0;
  }
}
