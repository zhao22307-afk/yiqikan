import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../room/room_entry.dart' show kLocalServerBase;

/// H11 房间回放页。
///
/// 数据源：房主手机上 `GET /local/replay?code=<code>&limit=200`。
/// 服务端只在内存里留帧（房间空了就丢），所以这里拉的是「本场房间的历史」，
/// 不是跨天记录 —— H11 原文（10 号 :186）也只要求 JSON 录制 + 回放器。
class RoomReplayPage extends StatefulWidget {
  const RoomReplayPage({
    super.key,
    required this.code,
    this.replayUrl,
    this.onSeek,
  });

  /// 房间码
  final String code;

  /// 房主本机固定是 127.0.0.1:8080；客人进来时用当前通道的 base
  final String? replayUrl;

  /// 点某条弹幕 → 由播放页判断「是不是同一部片子」再 seek
  final void Function(double seconds, String? mediaUrl)? onSeek;

  @override
  State<RoomReplayPage> createState() => _RoomReplayPageState();
}

class _RoomReplayPageState extends State<RoomReplayPage> {
  static final Dio _dio = Dio();
  List<Map<String, Object?>> _items = <Map<String, Object?>>[];
  Map<String, int> _stat = <String, int>{'chat': 0, 'danmaku': 0, 'state': 0};
  double _duration = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String base = widget.replayUrl ?? kLocalServerBase;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Response<dynamic> res = await _dio.get<dynamic>(
        '$base/local/replay',
        queryParameters: <String, Object?>{'code': widget.code, 'limit': 200},
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 6),
          validateStatus: (int? _) => true,
        ),
      );
      final Map<String, Object?> body =
          (jsonDecode('${res.data}') as Map<dynamic, dynamic>)
              .cast<String, Object?>();
      final List<Map<String, Object?>> items = <Map<String, Object?>>[];
      final Object? raw = body['items'];
      if (raw is List) {
        for (final Object? e in raw) {
          if (e is Map) items.add(e.cast<String, Object?>());
        }
      }
      final Map<String, int> stat = <String, int>{
        'chat': 0,
        'danmaku': 0,
        'state': 0,
      };
      double dur = 0;
      for (final Map<String, Object?> it in items) {
        final String type = '${it['type'] ?? ''}';
        if (stat.containsKey(type)) stat[type] = (stat[type] ?? 0) + 1;
        final double t = _num(it['t']);
        if (t > dur) dur = t;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _stat = stat;
        _duration = dur;
        _loading = false;
      });
      debugPrint('[YQK-REC] page code=${widget.code} n=${items.length} '
          'dur=${dur.toStringAsFixed(1)} chat=${stat['chat']} '
          'dm=${stat['danmaku']} state=${stat['state']}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
      debugPrint('[YQK-REC] page fail code=${widget.code} $e');
    }
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  static String _clock(double sec) {
    final int s = sec.round();
    final String m = (s ~/ 60).toString().padLeft(2, '0');
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  IconData _icon(String type) => switch (type) {
        'chat' => Icons.chat_bubble_outline,
        'danmaku' => Icons.subtitles_outlined,
        'state' => Icons.play_circle_outline,
        'control' => Icons.tune,
        'claim' => Icons.how_to_reg_outlined,
        'kick' => Icons.person_remove_alt_1_outlined,
        'muted' => Icons.volume_off_outlined,
        'transfer' => Icons.swap_horiz,
        'media' => Icons.movie_outlined,
        _ => Icons.fiber_manual_record,
      };

  String _text(Map<String, Object?> it) {
    final String type = '${it['type'] ?? ''}';
    switch (type) {
      case 'chat':
      case 'danmaku':
        return '${it['text'] ?? ''}';
      case 'state':
        return 'pos=${_num(it['pos']).toStringAsFixed(1)}s'
            '${it['playing'] == true ? ' 播放中' : ' 暂停'}';
      case 'control':
        return 'action=${it['action'] ?? ''}';
      case 'claim':
        return 'claim from=${it['from'] ?? ''}';
      case 'kick':
        return '踢出 ${it['memberId'] ?? it['target'] ?? ''}';
      case 'muted':
        return '禁言 ${it['memberId'] ?? it['target'] ?? ''}';
      case 'transfer':
        return '移交 → ${it['memberId'] ?? ''}';
      case 'media':
        return '换片 ${it['title'] ?? it['url'] ?? ''}';
      default:
        return '$type';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('本房间回放 ${widget.code}'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                _summary(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Text('拉不到回放：$_error',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Text(
                            '这场房间还没留下记录',
                            style: TextStyle(color: AppColors.textSub),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (BuildContext ctx, int i) {
                            final Map<String, Object?> it = _items[i];
                            final String type = '${it['type'] ?? ''}';
                            return ListTile(
                              dense: true,
                              leading: Icon(_icon(type),
                                  size: 18, color: AppColors.textSub),
                              title: Text(
                                _text(it).toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.text),
                              ),
                              subtitle: Text(
                                '${_clock(_num(it['t']))} · $type'
                                '${it['seq'] == null ? '' : ' · seq=${it['seq']}'}',
                                style: TextStyle(
                                    color: AppColors.textDim, fontSize: 11),
                              ),
                              onTap: type == 'danmaku' || type == 'state'
                                  ? () => widget.onSeek
                                      ?.call(_num(it['t']), it['mediaUrl'] as String?)
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _summary() => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.page, vertical: AppSpace.sm),
        color: AppColors.surface2,
        child: Row(
          children: <Widget>[
            Text('时长 ${_clock(_duration)}',
                style: TextStyle(color: AppColors.text, fontSize: 12)),
            const SizedBox(width: AppSpace.md),
            Text('聊天 ${_stat['chat']}',
                style: TextStyle(color: AppColors.textSub, fontSize: 12)),
            const SizedBox(width: AppSpace.sm),
            Text('弹幕 ${_stat['danmaku']}',
                style: TextStyle(color: AppColors.textSub, fontSize: 12)),
            const SizedBox(width: AppSpace.sm),
            Text('进度 ${_stat['state']}',
                style: TextStyle(color: AppColors.textSub, fontSize: 12)),
          ],
        ),
      );
}
