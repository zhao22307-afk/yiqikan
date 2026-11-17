import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'error_log.dart';

/// 崩溃兜底页（G7）：build 期异常、被 ErrorWidget.builder 接住时显示它。
///
/// 只做四件事：说明、错误摘要（前 200 字）、复制详情、重试（回首页）。
/// 不依赖任何 provider / 路由，保证「别的地方都坏了它也能画出来」。
class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    required this.detail,
    this.onRetry,
  });

  /// 已经把 stack 拼进来的完整文本（复制用）。
  final String detail;

  /// 重试回调；为空时按钮走 [ErrorReset.reset]。
  final VoidCallback? onRetry;

  String get _summary {
    final String flat = detail.replaceAll('\n', ' ').trim();
    if (flat.length <= 200) return flat;
    return '${flat.substring(0, 200)}…';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(
                Icons.sentiment_dissatisfied_outlined,
                size: 56,
                color: AppColors.warn,
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                '出了点问题',
                textAlign: TextAlign.center,
                style: AppText.title,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                '这页没画出来。可以重试，或把下面这段发给开发者。',
                textAlign: TextAlign.center,
                style: AppText.sub,
              ),
              const SizedBox(height: AppSpace.lg),
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Text(
                  _summary,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.sub.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                onPressed: () {
                  if (onRetry != null) {
                    onRetry!();
                    return;
                  }
                  ErrorReset.reset();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: detail));
                  debugPrint('[YQK-ERR] copied chars=${detail.length}');
                },
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('复制详情'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「重试」怎么算重试：本轮只做最简单的——通知根部重建，回到首页。
///
/// 真正的进程级恢复（restart_app 那种）要杀进程，这里不引入依赖也不重启 App：
/// 把当前 route 栈清空回首页即可，用户看到的是「回到首页」而不是白屏。
class ErrorReset {
  const ErrorReset._();

  /// 由 [YiqikanApp] 注册：回首页。
  static VoidCallback? onReset;

  static void reset() {
    debugPrint('[YQK-ERR] reset requested');
    // G7：用户点「重试」= 他要离开这张兜底页，先把日志落盘再回首页。
    // 不 await：不能被 IO 挡住界面。
    ErrorLog.flushNow();
    onReset?.call();
  }
}
