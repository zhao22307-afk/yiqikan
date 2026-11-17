import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/perm/permission_guide.dart';
import '../../theme/app_colors.dart';

/// 权限页（G10）：五行，每行「图标 + 名称 + 状态徽章 + 右侧按钮」。
///
/// 只申请用户主动点的那一项 —— 不在打开页面时批量弹框。
class PermissionPage extends StatefulWidget {
  const PermissionPage({super.key});

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage> {
  final Map<PermKind, PermState> _states = <PermKind, PermState>{
    for (final PermKind k in PermKind.values) k: PermState.notRequested,
  };

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    for (final PermKind k in PermKind.values) {
      try {
        _states[k] = await PermissionGuide.status(k);
      } on Object catch (e) {
        debugPrint('[YQK-PERM] status fail kind=${k.name} $e');
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
    debugPrint('[YQK-PERM] status ${_states.entries.map((MapEntry<PermKind, PermState> e) => '${e.key.name}=${e.value.name}').join(' ')}');
  }

  Future<void> _act(PermKind k) async {
    final PermState cur = _states[k] ?? PermState.notRequested;
    if (cur == PermState.granted) return;
    if (cur == PermState.permanentlyDenied || k == PermKind.installUnknown) {
      debugPrint('[YQK-PERM] open settings for kind=${k.name}');
      await PermissionGuide.openSettings();
      // 用户在系统页里改完回来要刷新，这里延迟一拍再读
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _loadAll();
      return;
    }
    final PermState next = await PermissionGuide.request(k);
    if (!mounted) return;
    setState(() => _states[k] = next);
    if (next == PermState.granted) {
      _toast('${PermissionGuide.titleOf(k)} 已开启');
    } else if (next == PermState.permanentlyDenied) {
      _toast('已永久拒绝，请到系统设置里开');
      await _loadAll();
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  IconData _iconOf(PermKind k) => switch (k) {
        PermKind.notification => Icons.notifications_active_outlined,
        PermKind.mediaVideo => Icons.video_library_outlined,
        PermKind.camera => Icons.photo_camera_outlined,
        PermKind.microphone => Icons.mic_none,
        PermKind.installUnknown => Icons.system_update_alt,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('权限'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_loadAll()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          for (final PermKind k in PermKind.values) _row(k),
          const SizedBox(height: AppSpace.lg),
          Text(
            '只在你点「申请」时才弹系统框，不会在打开页面时一起弹。'
            '「安装未知应用」不是运行时权限，只能去系统设置里开。',
            style: TextStyle(color: AppColors.textSub, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(PermKind k) {
    final PermState st = _states[k] ?? PermState.notRequested;
    final String? action = st.actionLabel;
    final Color badge = switch (st) {
      PermState.granted => AppColors.success,
      PermState.permanentlyDenied => AppColors.danger,
      PermState.denied => AppColors.warn,
      PermState.notRequested => AppColors.textSub,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: <Widget>[
          Icon(_iconOf(k), color: AppColors.textSub, size: 20),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(PermissionGuide.titleOf(k),
                    style: TextStyle(color: AppColors.text, fontSize: 14)),
                Text(PermissionGuide.whyOf(k),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSub, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(st == PermState.granted ? Icons.check_circle : Icons.circle,
                  size: 10, color: badge),
              const SizedBox(width: 4),
              Text(st.label, style: TextStyle(color: badge, fontSize: 11)),
            ],
          ),
          const SizedBox(width: AppSpace.sm),
          if (action == null)
            const SizedBox(width: 72)
          else
            SizedBox(
              width: 96,
              child: OutlinedButton(
                onPressed: () => unawaited(_act(k)),
                child: Text(action, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}
