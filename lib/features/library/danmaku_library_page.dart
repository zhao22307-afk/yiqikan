import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// F11 弹幕库（10 号 :149）：本地收藏的弹幕 + 搜索 + 快速回放。
///
/// 存的是 `danmaku_cache` 表里的 `mediaId='fav:<hash>'` 行（见 danmaku_dao.dart），
/// 表结构没动。
class DanmakuLibraryPage extends ConsumerStatefulWidget {
  const DanmakuLibraryPage({
    super.key,
    this.initialRoom,
    this.onRoomChanged,
    this.onJump,
  });

  /// 非空 = 默认只看这个房间收集的（房间内打开的入口）。
  /// 页内还能切到「全部收藏」，见下面的 ChoiceChip。
  final String? initialRoom;

  /// 房间筛选变化时通知调用方（目前只用于日志/联动预留）
  final ValueChanged<String?>? onRoomChanged;

  /// 点一条弹幕 → 让播放器跳到当时的位置。
  /// 由播放页注入，这里不持有 PlayerController（页面只认 url + 毫秒）。
  final void Function(String mediaUrl, int posMs)? onJump;

  @override
  ConsumerState<DanmakuLibraryPage> createState() =>
      _DanmakuLibraryPageState();
}

class _DanmakuLibraryPageState extends ConsumerState<DanmakuLibraryPage> {
  late final AppDatabase _db = ref.read(appDatabaseProvider);
  final TextEditingController _q = TextEditingController();

  bool _loading = true;
  List<DanmakuFav> _all = const <DanmakuFav>[];

  /// null = 全部收藏；非空 = 只看这个房间
  String? _room;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    unawaited(_load());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<DanmakuFav> list = await _db.danmakuDao.favList(room: _room);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
    debugPrint(
        '[YQK-DMLIB] filter room=${_room ?? 'all'} n=${list.length}');
  }

  void _pickRoom(String? room) {
    if (room == _room) return;
    setState(() {
      _room = room;
      _loading = true;
    });
    widget.onRoomChanged?.call(room);
    unawaited(_load());
  }

  void _search(String v) {
    final String k = v.trim();
    final int hit = k.isEmpty
        ? _all.length
        : _all.where((DanmakuFav f) => f.text.contains(k)).length;
    debugPrint('[YQK-DMLIB] search q=$k hit=$hit');
    setState(() {});
  }

  Future<void> _remove(DanmakuFav f) async {
    await _db.danmakuDao.favRemove(f.id);
    debugPrint('[YQK-DMLIB] remove id=${f.id}');
    await _load();
  }

  List<DanmakuFav> get _visible {
    final String k = _q.text.trim();
    if (k.isEmpty) return _all;
    return _all.where((DanmakuFav f) => f.text.contains(k)).toList();
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _pos(double s) {
    final int total = s.round();
    final int m = total ~/ 60;
    final int sec = total % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.initialRoom == null
            ? '弹幕库'
            : '本房间弹幕 · ${widget.initialRoom}'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.page, AppSpace.sm, AppSpace.page, AppSpace.sm),
            child: TextField(
              controller: _q,
              onChanged: _search,
              style: TextStyle(color: AppColors.text, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜弹幕文本',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
          if (widget.initialRoom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.page, 0, AppSpace.page, AppSpace.sm),
              child: Row(
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('全部收藏'),
                    selected: _room == null,
                    onSelected: (_) => _pickRoom(null),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  ChoiceChip(
                    label: Text('本房间 ${widget.initialRoom}'),
                    selected: _room != null,
                    onSelected: (_) => _pickRoom(widget.initialRoom),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? Center(
                        child: Text('还没有收藏的弹幕，长按弹幕可以收藏',
                            style: TextStyle(color: AppColors.textSub)),
                      )
                    : ListView.separated(
                        itemCount: _visible.length,
                        separatorBuilder:
                            (BuildContext _, int __) => const Divider(height: 1),
                        itemBuilder: (BuildContext c, int i) {
                          final DanmakuFav f = _visible[i];
                          return ListTile(
                            dense: true,
                            onTap: widget.onJump == null
                                ? null
                                : () => widget.onJump!(
                                      f.mediaUrl,
                                      (f.pos * 1000).round(),
                                    ),
                            title: Text(f.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppColors.text, fontSize: 13)),
                            subtitle: Text(
                              '${f.source} · ${_pos(f.pos)} · ${_hm(f.atTime)}',
                              style: TextStyle(
                                  color: AppColors.textSub, fontSize: 11),
                            ),
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: AppColors.textSub),
                              onPressed: () => unawaited(_remove(f)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}