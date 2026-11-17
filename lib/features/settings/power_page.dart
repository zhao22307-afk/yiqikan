import 'package:flutter/material.dart';

import '../../core/power/power_guide.dart';
import '../../theme/app_colors.dart';

/// G13：省电与后台。
///
/// 三节：当前状态 / 「去设置」/ 后台行为说明（纯文字）。
/// 不做任何静默申请：`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 只在
/// 用户点按钮时发，且 intent 里带 `package:` 只针对本应用。
class PowerPage extends StatefulWidget {
  const PowerPage({super.key});

  @override
  State<PowerPage> createState() => _PowerPageState();
}

class _PowerPageState extends State<PowerPage> {
  bool? _ignoring;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool? v = await PowerGuide.isIgnoringBattery();
    debugPrint('[YQK-POWER] page status ignoring=$v');
    if (mounted) setState(() => _ignoring = v);
  }

  Future<void> _openSettings() async {
    final bool ok = await PowerGuide.requestIgnoreBattery();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打不开系统页，去「设置 → 电池 → 应用」里手动加白名单')),
      );
      return;
    }
    // 用户从系统页回来时状态可能变了，回来再查一次
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bool? ignoring = _ignoring;
    final String statusText = ignoring == null
        ? '未知（查询失败）'
        : ignoring
            ? '已在白名单：系统不会限制后台'
            : '不在白名单：后台可能被限制';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('省电与后台'),
        backgroundColor: AppColors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: <Widget>[
          // ① 当前状态
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('当前状态', style: AppText.section),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: <Widget>[
                    Icon(
                      ignoring == true ? Icons.verified : Icons.battery_alert,
                      size: 20,
                      color: ignoring == true ? AppColors.success : AppColors.warn,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text(statusText, style: AppText.body)),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                // ② 去设置
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.battery_saver_outlined),
                    label: const Text('去设置电池优化白名单'),
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '用途：让「一起看」在锁屏/切后台时不被系统冻结，房间和屏幕共享才不会掉。'
                  '这个按钮只打开系统页面，加不加白名单由你决定。',
                  style: AppText.sub,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          // ③ 后台行为说明
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('后台会怎样', style: AppText.section),
                const SizedBox(height: AppSpace.sm),
                for (final (String title, String body) in PowerGuide.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: AppText.body),
                        const SizedBox(height: AppSpace.xxs),
                        Text(body, style: AppText.sub),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
