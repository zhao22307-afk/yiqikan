/// 跟随播放的纯规则（不碰播放器、不碰 UI，单测直接打这里）。
///
/// 为什么单独抽出来：跟随逻辑一旦写进 widget，就只能靠真机两开验，
/// 回归成本高；把「要不要跟」「跟到哪儿」抽成纯函数，改完跑单测即可。
library;

/// 是否应该应用这条权威 state。
///
/// - 自己发的 state 不回灌（否则房主 seek → 广播 → 房主再 seek 无限循环）
/// - 房主在 host 模式是权威源，不跟别人；**free 模式下房主也要跟**
/// - 本地拖动期间不响应（否则刚拖完就被弹回去）
bool shouldFollowState({
  required String me,
  required String? by,
  required bool isHost,
  required bool seekingLocally,
  bool freeMode = false,
}) {
  if (isHost && !freeMode) return false;
  if (me.isNotEmpty && by == me) return false;
  if (seekingLocally) return false;
  return true;
}

/// 目标位置：播放中按「本地单调时钟」外推，暂停时停在 position。
///
/// 入参必须是**收到帧之后本地经过的毫秒**（Stopwatch），
/// 不能用帧里的服务端时间戳做差 —— 两台机时钟不同步会算出负数（把客人拉回过去）
/// 或虚高（一直往前跳）。盒子和电视不走 NTP 时差几秒很常见。
double followTarget({
  required double position,
  required bool playing,
  required double rate,
  required int elapsedMsLocal,
}) {
  if (!playing) return position;
  if (elapsedMsLocal <= 0) return position;
  final double t = position + elapsedMsLocal / 1000.0 * rate;
  return t < 0 ? 0 : t;
}

/// 偏差是否大到需要硬 seek（默认 2 秒）。
bool needsSeek(double target, double mine, {double threshold = 2}) {
  return (target - mine).abs() >= threshold;
}

/// 13 号 D21：偏差三档。0–300ms 不动，300–700ms 变速追，>700ms 硬跳。
enum FollowAction { none, speed, seek }

/// 按偏差挑一档。纯函数：不碰播放器、不读全局。
FollowAction decideFollow(double target, double mine,
    {double fineSec = 0.3, double coarseSec = 0.7}) {
  final double d = (target - mine).abs();
  if (d < fineSec) return FollowAction.none;
  if (d < coarseSec) return FollowAction.speed;
  return FollowAction.seek;
}

/// 追赶倍率：偏差从 0.3→0.7 线性放大到 base*1.30；方向由 target-mine 决定。
/// 超出 [fine, coarse) 区间一律返回 base（不动）。
double catchUpRate(double target, double mine,
    {double base = 1.0, double fineSec = 0.3, double coarseSec = 0.7}) {
  final double d = target - mine;
  final double a = d.abs();
  if (a < fineSec || a >= coarseSec) return base;
  final double k = ((a - fineSec) / (coarseSec - fineSec)).clamp(0.0, 1.0);
  final double factor = 1.0 + 0.30 * k;
  return d > 0 ? base * factor : base / factor;
}
