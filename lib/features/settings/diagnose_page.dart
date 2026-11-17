import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/error/error_log.dart';
import '../../platform/room/channel.dart';
import '../../platform/room/room_client.dart';
import '../../platform/room/room_snapshot.dart';
import '../../theme/app_colors.dart';

/// 诊断页（G6）：六段信息 + 复制 / 导出 / 清空。
///
/// 只读，不写任何业务状态；所有网络请求都带超时，失败就显示「未知」。
class DiagnosePage extends StatefulWidget {
  const DiagnosePage({super.key});

  @override
  State<DiagnosePage> createState() => _DiagnosePageState();
}

class _DiagnosePageState extends State<DiagnosePage> {
  static const String _base = 'http://127.0.0.1:8080';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 2),
    validateStatus: (int? _) => true,
  ));

  String _version = '…';
  String _build = '';

  /// `/health` 的结果；null = 请求失败或超时。
  Map<String, dynamic>? _health;
  String _healthErr = '';

  /// `/local/reach` 的结果。
  Map<String, dynamic>? _reach;
  String _reachErr = '';

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _loadApp();
    await _loadHealth();
    await _loadReach();
    if (!mounted) return;
    setState(() => _loading = false);
    debugPrint('[YQK-DIAG] load health=${_health != null} reach=${_reach != null} '
        'errors=${ErrorLog.all.length}');
  }

  Future<void> _loadApp() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _version = '未知（$e）');
    }
  }

  Future<void> _loadHealth() async {
    try {
      final Response<dynamic> r = await _dio.get<dynamic>('$_base/health');
      final Object? data = r.data;
      final Map<String, dynamic>? j =
          data is Map ? Map<String, dynamic>.from(data) : null;
      if (!mounted) return;
      setState(() {
        _health = j;
        _healthErr = j == null ? '返回不是 JSON' : '';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _health = null;
        _healthErr = '$e';
      });
    }
  }

  Future<void> _loadReach() async {
    try {
      final Response<dynamic> r = await _dio.get<dynamic>('$_base/local/reach');
      final Object? data = r.data;
      final Map<String, dynamic>? j =
          data is Map ? Map<String, dynamic>.from(data) : null;
      if (!mounted) return;
      setState(() {
        _reach = j;
        _reachErr = j == null ? '返回不是 JSON' : '';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _reach = null;
        _reachErr = '$e';
      });
    }
  }

  /// 六段汇总成一段纯文本（复制全部用，也是「粘给开发者」的正式格式）。
  String _digest() {
    final RoomClient? rc = RoomClient.current;
    final RoomSnapshot? snap = rc?.snapshot.value;
    final Channel? ch = rc?.channel;
    final List<RoomMember> members = snap?.members ?? const <RoomMember>[];
    final int online = members.where((RoomMember m) => m.online).length;
    final StringBuffer b = StringBuffer()
      ..writeln('一起看 诊断')
      ..writeln('app      ${_version}${_build.isEmpty ? '' : ' ($_build)'}')
      ..writeln('service  ${_health == null ? '未知${_healthErr.isEmpty ? '' : '：$_healthErr'}' : 'ok port=${_health!['port'] ?? 8080} status=${_health!['status'] ?? ''}'}')
      ..writeln('channel  ${ch == null ? '（本次进程没进过房）' : '${ch.id} / ${ch.name} rtt=${ch.rttMs}ms state=${ch.state}'}')
      ..writeln('lan      ${_reach?['lan'] ?? '未知'}${_reachErr.isEmpty ? '' : '（$_reachErr）'}');
    final Object? addrs = _reach?['addresses'];
    if (addrs is List && addrs.isNotEmpty) {
      for (final Object? a in addrs) {
        if (a is Map) b.writeln('         ${a['kind'] ?? ''} ${a['ip'] ?? ''} (${a['iface'] ?? ''})');
      }
    }
    b
      ..writeln('room     ${rc?.roomCode ?? '—'} members=${members.length} online=$online')
      ..writeln('errors   ${ErrorLog.all.length} / ${ErrorLog.maxEntries}')
      ..writeln();
    b.write(ErrorLog.exportText());
    return b.toString();
  }

  Future<void> _copyAll() async {
    final String text = _digest();
    await Clipboard.setData(ClipboardData(text: text));
    debugPrint('[YQK-DIAG] copy len=${text.length}');
    _toast('已复制 ${text.length} 字');
  }

  /// B2：导出崩溃日志。优先让用户选保存位置（SAF），取消就退回剪贴板。
  Future<void> _exportLog() async {
    try {
      final File f = await ErrorLog.file();
      final List<int> bytes =
          f.existsSync() ? await f.readAsBytes() : utf8.encode(ErrorLog.exportText());
      final Uint8List data = Uint8List.fromList(bytes);
      final Uri? picked = await FilePicker.saveFile(
        dialogTitle: '导出崩溃日志',
        fileName: 'yiqikan_crash.log',
        bytes: data,
        mimeType: 'text/plain',
      );
      final String? path = picked?.toString();
      debugPrint('[YQK-DIAG] export bytes=${data.length} path=${path ?? '(取消)'}');
      if (path == null) {
        await Clipboard.setData(ClipboardData(text: utf8.decode(bytes, allowMalformed: true)));
        _toast('没有选位置，已复制到剪贴板');
      } else {
        _toast('已导出 $path');
      }
    } on Object catch (e) {
      debugPrint('[YQK-DIAG] export fail: $e');
      _toast('导出失败：$e');
    }
  }

  Future<void> _clear() async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('清空最近错误？'),
            content: const Text('只清内存里的这一份列表，已落盘的 crash.log 不动。'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    ErrorLog.clear();
    if (!mounted) return;
    setState(() {});
    _toast('已清空');
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final RoomClient? rc = RoomClient.current;
    final RoomSnapshot? snap = rc?.snapshot.value;
    final List<RoomMember> members = snap?.members ?? const <RoomMember>[];
    final int online = members.where((RoomMember m) => m.online).length;
    final Channel? ch = rc?.channel;
    final List<ErrorEntry> errs = ErrorLog.recent(20);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('诊断'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_load()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          _card('应用', <Widget>[
            _kv('版本', '$_version${_build.isEmpty ? '' : ' ($_build)'}'),
            _kv('包名', 'top.yiqikan.app.debug'),
          ]),
          _card('服务', <Widget>[
            _kv('端口', '8080'),
            _kv(
              '状态',
              _health == null
                  ? (_healthErr.isEmpty ? '未知' : '未知（超时/失败）')
                  : '${_health!['status'] ?? 'ok'} · rooms=${_health!['rooms'] ?? '-'} users=${_health!['users'] ?? '-'}',
            ),
          ]),
          _card('网络', <Widget>[
            _kv('通道', ch == null ? '（本次进程没进过房）' : '${ch.id} / ${ch.name}'),
            _kv('RTT', ch == null ? '—' : '${ch.rttMs} ms'),
            _kv('LAN', '${_reach?['lan'] ?? '未知'}'),
            if (_reach?['addresses'] is List)
              for (final Object? a in _reach!['addresses'] as List<dynamic>)
                if (a is Map)
                  _kv('地址 ${a['kind'] ?? ''}', '${a['ip'] ?? ''} · ${a['iface'] ?? ''}'),
          ]),
          _card('房间', <Widget>[
            _kv('房间码', rc?.roomCode ?? '—'),
            _kv('成员', '${members.length} 人 · 在线 $online'),
            for (final RoomMember m in members.take(6))
              _kv(m.isOwner ? '房主' : '成员', '${m.nickname}${m.online ? '' : '（离线）'}'),
          ]),
          _card('最近错误（${errs.length}）', <Widget>[
            if (errs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Text('没有记录到错误', style: TextStyle(color: AppColors.textSub)),
              )
            else
              for (final ErrorEntry e in errs)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: AppSpace.sm),
                  title: Text('${e.clock} · ${e.kind}',
                      style: TextStyle(color: AppColors.text, fontSize: 13)),
                  subtitle: Text(e.firstLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSub, fontSize: 12)),
                  children: <Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpace.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: SelectableText(
                        e.stackText().isEmpty ? '(无栈)' : e.stackText(),
                        style: TextStyle(
                          color: AppColors.textSub,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
          ]),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
          child: Row(
            children: <Widget>[
              Expanded(child: FilledButton.icon(
                onPressed: () => unawaited(_copyAll()),
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('复制全部'),
              )),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => unawaited(_exportLog()),
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('导出日志'),
              )),
              const SizedBox(width: AppSpace.sm),
              IconButton(
                tooltip: '清空',
                onPressed: () => unawaited(_clear()),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> rows) => Container(
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xs),
            ...rows,
          ],
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 92,
              child: Text(k, style: TextStyle(color: AppColors.textSub, fontSize: 12)),
            ),
            Expanded(
              child: SelectableText(v,
                  style: TextStyle(color: AppColors.text, fontSize: 12)),
            ),
          ],
        ),
      );
}

/// 让「应用私有目录」这种绝对路径在报告里有个固定出处（也避免 IDE 提示未用 import）。
Future<String> debugSupportDir() async => (await getApplicationSupportDirectory()).path;
