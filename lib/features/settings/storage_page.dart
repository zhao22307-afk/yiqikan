import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../providers/app_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// F8 存储与缓存（10 号 :135-151）。
///
/// 分区：缓存(cacheDir) / 播放临时文件(media_kit 的 NativeReferenceHolder.*) /
/// 数据库(只读) / 片源·收藏·历史(只读条数)。
/// 清理只碰前两项；databases 与 shared_prefs 一律不动。
class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> {
  bool _loading = true;
  bool _busy = false;
  Map<String, int> _size = const <String, int>{};
  int _favCount = 0;
  int _histCount = 0;
  int _sourceCount = 0;
  String? _lastFreed;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Map<String, int> size = await _measure();
    final db = ref.read(appDatabaseProvider);
    final int fav = (await db.favoriteDao.all()).length;
    final int hist = (await db.historyDao.recent(limit: 1 << 20)).length;
    final int src = (await db.sourceDao.all(enabledOnly: false)).length;
    if (!mounted) return;
    setState(() {
      _size = size;
      _favCount = fav;
      _histCount = hist;
      _sourceCount = src;
      _loading = false;
    });
    debugPrint('[YQK-STORE] cache=${size['cache']} temp=${size['temp']} '
        'db=${size['db']} fav=$fav hist=$hist src=$src');
  }

  /// 目录体积在 isolate 里算（文件多时不卡 UI）
  Future<Map<String, int>> _measure() async {
    final Directory cache = await getTemporaryDirectory();
    final Directory support = await getApplicationSupportDirectory();
    final String dbPath = p.join(support.path, 'yiqikan.db');
    return Isolate.run<Map<String, int>>(() {
      int dirSize(String path, {bool Function(String name)? only}) {
        final Directory d = Directory(path);
        if (!d.existsSync()) return 0;
        int total = 0;
        // 递归：缓存/临时目录里通常还有一层层子目录（cache/img/…），
        // 只看第一层会把它们全算成 0。
        for (final FileSystemEntity e in d.listSync(recursive: true)) {
          if (e is! File) continue;
          if (only != null && !only(p.basename(e.path))) continue;
          try {
            total += e.lengthSync();
          } catch (_) {
            // 正在写的文件量不到就跳过，不影响整页
          }
        }
        return total;
      }

      bool isTemp(String name) => name.startsWith('NativeReferenceHolder');
      final int db = <String>[dbPath, '$dbPath-wal', '$dbPath-shm']
          .where((String f) => File(f).existsSync())
          .fold<int>(0, (int a, String f) => a + File(f).lengthSync());
      return <String, int>{
        'cache': dirSize(cache.path),
        'temp': dirSize(support.path, only: isTemp),
        'db': db,
      };
    });
  }

  Future<void> _clean() async {
    final int target = (_size['cache'] ?? 0) + (_size['temp'] ?? 0);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: Text('要删除 ${_mb(target)} 缓存吗？\n'
            '数据库、收藏、历史、登录与房间记录都不会动。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    // 只把字符串带进 isolate：带 Directory / State 进去会让 Isolate.spawn
    // 抛 “Illegal argument in isolate message”，清理就永远停在「正在清理…」。
    final String cachePath = (await getTemporaryDirectory()).path;
    final String supportPath = (await getApplicationSupportDirectory()).path;
    // 清理体放顶层函数：闭包只要带住所在 async 帧里的对象（Completer / State），
    // Isolate.spawn 就会抛 “Illegal argument in isolate message”。
    final int freed = await _runClean(cachePath, supportPath);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastFreed = '清理完成，释放 ${_mb(freed)}';
    });
    debugPrint('[YQK-STORE] clean freed=$freed');
    await _load();
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final int cache = _size['cache'] ?? 0;
    final int temp = _size['temp'] ?? 0;
    final int dbSize = _size['db'] ?? 0;
    final int total = cache + temp + dbSize;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('存储与缓存')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.page),
              children: <Widget>[
                _section('可清理', <Widget>[
                  _row('缓存', _mb(cache), '临时下载、封面缩略图'),
                  _row('播放临时文件', _mb(temp),
                      'media_kit 的 NativeReferenceHolder.*'),
                ]),
                _section('只读', <Widget>[
                  _row('数据库', _mb(dbSize), 'yiqikan.db（收藏/历史都在里面）'),
                  _row('片源', '$_sourceCount 条', '只显示条数'),
                  _row('收藏 / 稍后看', '$_favCount 条', '只显示条数'),
                  _row('历史', '$_histCount 条', '只显示条数'),
                ]),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: <Widget>[
                    Text('总占用', style: AppText.sub),
                    const Spacer(),
                    Text(_mb(total),
                        style: TextStyle(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_clean()),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text(_busy ? '正在清理…' : '清理缓存'),
                ),
                if (_lastFreed != null) ...<Widget>[
                  const SizedBox(height: AppSpace.sm),
                  Text(_lastFreed!,
                      style: TextStyle(color: AppColors.textSub)),
                ],
                const SizedBox(height: AppSpace.md),
                Text('清理只删前两项；数据库、shared_prefs（登录与房间记录）不动。',
                    style: TextStyle(color: AppColors.textSub, height: 1.6)),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: TextStyle(
                  color: AppColors.textSub,
                  fontSize: 13,
                  letterSpacing: 1)),
          const SizedBox(height: AppSpace.xs),
          ...children,
          const SizedBox(height: AppSpace.md),
        ],
      );

  Widget _row(String name, String size, String hint) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: TextStyle(color: AppColors.text)),
                  Text(hint,
                      style: TextStyle(
                          color: AppColors.textSub, fontSize: 11)),
                ],
              ),
            ),
            Text(size, style: TextStyle(color: AppColors.textSub)),
          ],
        ),
      );
}

/// 顶层函数（不在 State 里）：递归删缓存与播放临时文件，返回释放的字节数。
/// 放顶层是为了让 Isolate.run 只带两个字符串进去 —— 闭包带住 State/Completer 时
/// Isolate.spawn 会抛 “Illegal argument in isolate message”，清理会卡在「正在清理…」。
int cleanStorageDirs(String cachePath, String supportPath) {
  int gone = 0;
  void wipe(String path, {bool Function(String name)? only}) {
    final Directory d = Directory(path);
    if (!d.existsSync()) return;
    for (final FileSystemEntity e in d.listSync(recursive: true)) {
      if (e is! File) continue;
      if (only != null && !only(p.basename(e.path))) continue;
      try {
        gone += e.lengthSync();
        e.deleteSync();
      } catch (_) {
        // 被播放器占着的文件删不掉，下次再清
      }
    }
  }

  wipe(cachePath);
  wipe(supportPath, only: (String n) => n.startsWith('NativeReferenceHolder'));
  return gone;
}

/// 清理用 Isolate.spawn 而不是 Isolate.run：Isolate.run 要把闭包发过去，
/// 闭包会带住 FlutterBinding（_firstFrameCompleter），发送时直接抛
/// “Illegal argument in isolate message”。这里只发 SendPort + 两个字符串。
Future<int> _runClean(String cachePath, String supportPath) async {
  final ReceivePort rp = ReceivePort();
  await Isolate.spawn(_cleanEntry, <Object>[rp.sendPort, cachePath, supportPath]);
  final Object? msg = await rp.first;
  rp.close();
  return msg is int ? msg : 0;
}

void _cleanEntry(List<Object> args) {
  final SendPort port = args[0] as SendPort;
  port.send(cleanStorageDirs(args[1] as String, args[2] as String));
}