/// H4：片头/片尾的「该不该跳」判定。
///
/// 纯函数 + 一个内部「本片已跳过片头」标记，无副作用、不碰播放器，可以直接单测。
/// 片头片尾的秒数来自两处：片源自带的章节（mpv chapter-list），或用户手动标记
/// （chapter_marks 表）；本文件不关心来源，只认两个 double。
library;

/// 判定结果
enum SkipAction {
  /// 不动
  none,

  /// 跳到片头结束（玩家从片头/前情提要进入正片）
  toIntroEnd,

  /// 到片尾开始（保留给上层：真正的语义是「别看了，下一集」）
  toOutroStart,
}

/// 一次播放会话内复用同一个实例；切片/换片时调 [reset]。
class ChapterSkip {
  bool _introDone = false;
  bool _outroHit = false;

  /// 本片是否已经跳过片头（C-V4：拖回去不再跳）
  bool get introSkipped => _introDone;

  /// 上一次 decide 是否命中片尾
  bool get outroHit => _outroHit;

  /// 换片 / 重开时复位
  void reset() {
    _introDone = false;
    _outroHit = false;
  }

  /// 判定当前位置该不该跳。
  ///
  /// - [introEnd] / [outroStart] 传 -1 表示未设
  /// - [tolerance] 已经在目标附近就别跳（防抖，避免 seek 完又命中）
  /// - 片头：只在**刚开始播**（pos 明显早于片头结束）时跳一次，之后不论怎么拖都不跳
  /// - 片尾：命中只置 [outroHit] 并返回 [SkipAction.none] —— 「跳过片尾」的语义是
  ///   播完/下一集，由上层决定，本函数不做动作
  SkipAction decide({
    required double pos,
    required double duration,
    required double introEnd,
    required double outroStart,
    required bool skipIntro,
    required bool skipOutro,
    double tolerance = 1.5,
  }) {
    _outroHit = false;

    // ① 片头：pos 落在 [0, introEnd - tolerance) 且本片还没跳过
    if (skipIntro && introEnd > 0 && pos >= 0 && pos < introEnd - tolerance) {
      if (!_introDone) {
        _introDone = true;
        return SkipAction.toIntroEnd;
      }
    }

    // ② 片尾：到点只报告，不自己动
    if (skipOutro && outroStart > 0 && duration > 0 && pos >= outroStart) {
      _outroHit = true;
      return SkipAction.none;
    }

    return SkipAction.none;
  }
}
