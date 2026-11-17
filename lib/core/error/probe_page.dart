import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 调试用：build 期直接抛，验证 [ErrorWidget.builder] 换成了 ErrorPage（G7 / D-V2）。
///
/// 只在 debug 构建里从设置的「开发诊断」区块进入，不进任何正常路径。
class BoomPage extends StatelessWidget {
  const BoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    throw StateError('调试用的 build 期异常（BoomPage）');
  }
}

/// 调试用：造一条没人 await 的异步异常，验证 [PlatformDispatcher.onError]（D-V3）。
void fireAsyncError() {
  debugPrint('[YQK-ERR] probe fire async error');
  unawaited(Future<void>.error(StateError('调试用的异步异常（probe）')));
}
