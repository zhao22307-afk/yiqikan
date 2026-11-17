import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/download/download_engine.dart';
import '../../data/download/download_task.dart';
import '../../features/player/player_controller.dart';
import '../../routing/routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// F2 下载列表：进度 / 速度 / 暂停继续 / 删除 / 全部暂停继续 / 清空已完成。
///
/// 数据全部来自 [DownloadEngine.tasks]（ValueNotifier），不在 build 里 setState。
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final DownloadEngine _engine = DownloadEngine.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_engine.ensureReady());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _open(DownloadTask t) async {
    debugPrint('[YQK-DL] open path=${t.savePath}');
    await context.push<Object?>(
      Routes.player,
      extra: PlayerMedia(
        id: t.id,
        title: t.title,
        url: t.savePath,
        sourceKind: 'download',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = ValueListenableBuilder<List<DownloadTask>>(
      valueListenable: _engine.tasks,
      builder: (BuildContext context, List<DownloadTask> list, Widget? _) {
        if (list.isEmpty) {
          return Center(
            child: Text('还没有下载，在片子详情里点『下载』',
                style: TextStyle(color: AppColors.textSub)),
          );
        }
        return ListView.separated(
          itemCount: list.length + 1,
          separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int i) {
            if (i == 0) return _toolbar();
            return _tile(list[i - 1]);
          },
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('下载')),
      body: body,
    );
  }

  Widget _toolbar() => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.page, AppSpace.sm, AppSpace.page, AppSpace.sm),
        child: Row(
          children: <Widget>[
            TextButton(
              onPressed: () => unawaited(_engine.pauseAll()),
              child: const Text('全部暂停'),
            ),
            TextButton(
              onPressed: () => unawaited(_engine.resumeAll()),
              child: const Text('全部继续'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => unawaited(_engine.clearDone()),
              child: const Text('清空已完成'),
            ),
          ],
        ),
      );

  Widget _tile(DownloadTask t) {
    final bool canResume =
        t.state == DownloadState.paused || t.state == DownloadState.failed;
    final String stateText = switch (t.state) {
      DownloadState.queued => '排队中',
      DownloadState.running => '下载中',
      DownloadState.paused => '已暂停',
      DownloadState.done => '已完成',
      DownloadState.failed => '失败${t.error == null ? '' : '：${t.error}'}',
    };
    final String speed = t.state == DownloadState.running && t.speedKbps > 0
        ? ' · ${t.speedKbps.toStringAsFixed(0)} KB/s'
        : '';
    return ListTile(
      title: Text(t.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.text)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: t.state == DownloadState.done ? 1 : t.progress,
              minHeight: 4,
              backgroundColor: AppColors.bg,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$stateText · ${DownloadTask.sizeText(t.received)}'
            ' / ${DownloadTask.sizeText(t.total)}$speed',
            style: TextStyle(color: AppColors.textSub, fontSize: 11),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (t.state == DownloadState.done)
            IconButton(
              tooltip: '播放',
              icon: Icon(Icons.play_arrow_outlined,
                  color: AppColors.textSub),
              onPressed: () => unawaited(_open(t)),
            )
          else if (canResume)
            IconButton(
              tooltip: '继续',
              icon: Icon(Icons.play_circle_outline,
                  color: AppColors.textSub),
              onPressed: () => unawaited(_engine.resume(t.id)),
            )
          else
            IconButton(
              tooltip: '暂停',
              icon: Icon(Icons.pause_circle_outline,
                  color: AppColors.textSub),
              onPressed: () => unawaited(_engine.pause(t.id)),
            ),
          IconButton(
            tooltip: '删除',
            icon: Icon(Icons.delete_outline, color: AppColors.textSub),
            onPressed: () async {
              await _engine.remove(t.id);
              _toast('已删除');
            },
          ),
        ],
      ),
    );
  }
}