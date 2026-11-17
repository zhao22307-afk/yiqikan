import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logger.dart';
import '../../core/utils/time_format.dart';
import '../../platform/player/kernel_factory.dart';
import '../../theme/app_theme.dart';
import 'player_controller.dart';

/// 播放器高级面板（15 §A11，只在 debug 构建可见）。
///
/// 只读诊断：把内核属性、内核选择、日志导出放一处，
/// 免得为了一次排查在正式 UI 里留调试入口（06 §2 MUST NOT 第 11 条）。
class PlayerAdvancedPage extends StatefulWidget {
  const PlayerAdvancedPage({super.key, this.controller});

  final PlayerController? controller;

  @override
  State<PlayerAdvancedPage> createState() => _PlayerAdvancedPageState();
}

class _PlayerAdvancedPageState extends State<PlayerAdvancedPage> {
  /// 15 §A11 指定的属性 + 几条排查必看项
  static const List<String> _keys = <String>[
    'hwdec-current',
    'vo-configured',
    'video-params',
    'frame-drop-count',
    'demuxer-cache-duration',
    'audio-codec-name',
    'video-codec-name',
    'aid',
    'width',
    'height',
    'video-aspect-override',
  ];

  PlayerController? _controller;
  Map<String, String?> _props = <String, String?>{};
  Timer? _ticker;
  String? _exported;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    unawaited(_refresh());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final PlayerController? c = _controller;
    if (c == null || !mounted) return;
    final Map<String, String?> values = await c.kernel.debugProperties(_keys);
    if (!mounted) return;
    setState(() => _props = values);
  }

  int get _filledCount =>
      _props.values.where((String? v) => v != null && v.trim().isNotEmpty).length;

  Future<void> _exportLogs() async {
    final Directory dir = await getApplicationSupportDirectory();
    final Directory logs = Directory('${dir.path}/logs');
    if (!logs.existsSync()) logs.createSync(recursive: true);
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final File file = File('${logs.path}/player-advanced-$stamp.txt');
    final List<String> lines = <String>[
      '# 一起看 · 播放器高级面板导出',
      '内核：${_controller?.kernel.name ?? '-'}（偏好 ${_controller?.kernelKind.label ?? '-'}）',
      '时间：${DateTime.now().toIso8601String()}',
      '',
      '## 属性',
      for (final String k in _keys) '$k = ${_props[k] ?? '—'}',
      '',
      '## 日志（最近 ${AppLog.tail().length} 行）',
      ...AppLog.tail(),
    ];
    await file.writeAsString(lines.join('\n'));
    if (!mounted) return;
    setState(() => _exported = file.path);
  }

  @override
  Widget build(BuildContext context) {
    final PlayerController? c = _controller;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('播放器高级面板'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_refresh()),
          ),
        ],
      ),
      body: c == null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpace.page),
                child: Text(
                  '这个面板要从播放页进入：设置 → 高级面板。\n'
                  '没有在播的片子时，这里没有属性可看。',
                  style: TextStyle(color: AppColors.textSub, height: 1.6),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpace.page),
              children: <Widget>[
                _section('当前播放'),
                _kv('标题', c.media?.title ?? '—'),
                _kv('内核', '${c.kernel.name}（可用：${KernelFactory.fvpAvailable ? 'mpv / fvp' : 'mpv'}）'),
                _kv('位置', '${formatDuration(c.position)} / ${formatDuration(c.duration)}'),
                _kv('倍速', formatRate(c.rate)),
                const SizedBox(height: AppSpace.md),
                _section('播放内核'),
                for (final KernelKind k in KernelKind.values)
                  RadioListTile<KernelKind>(
                    value: k,
                    // ignore: deprecated_member_use
                    groupValue: c.kernelKind,
                    // ignore: deprecated_member_use
                    onChanged: (KernelKind? v) {
                      if (v == null) return;
                      unawaited(c.setKernelKind(v));
                    },
                    title: Text(k.label,
                        style: TextStyle(color: AppColors.text)),
                    subtitle: k == KernelKind.auto
                        ? Text('优先 mpv；fvp 起不来会自动退回',
                            style: TextStyle(color: AppColors.textSub))
                        : null,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: AppSpace.md),
                _section('内核属性（$_filledCount/${_keys.length} 有值）'),
                for (final String k in _keys) _kv(k, _props[k] ?? '—'),
                const SizedBox(height: AppSpace.md),
                _section('日志'),
                Row(
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: () => unawaited(_exportLogs()),
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('导出日志'),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        unawaited(Clipboard.setData(
                          ClipboardData(text: AppLog.tail().join('\n')),
                        ));
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(content: Text('最近 500 行已复制')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制'),
                    ),
                  ],
                ),
                if (_exported != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: SelectableText(
                      '已导出：$_exported',
                      style: TextStyle(
                          color: AppColors.success, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: AppSpace.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: SelectableText(
                    AppLog.tail(60).isEmpty ? '（还没有日志）' : AppLog.tail(60).join('\n'),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: AppColors.textSub,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Text(title, style: AppText.section),
      );

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 150,
              child: Text(key,
                  style: TextStyle(color: AppColors.textSub, fontSize: 12)),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: TextStyle(color: AppColors.text, fontSize: 12),
              ),
            ),
          ],
        ),
      );
}