import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/db/app_database.dart';
import '../../data/local/prefs.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import 'backup_merge.dart';

/// F7 数据备份与恢复（10 号 :145）：导出 / 导入一份 JSON。
///
/// **只导用户数据，不导凭据**：
/// - accounts 只留 kind / displayName / username，cookie 与 token 在 SecureStore，压根不碰；
/// - rooms 只留 code / name / mode / joinUrl / hostName，passwordHash 与 extra 不导；
/// - settings 只导 pref 白名单里的非敏感键（PrefKeys.all 本身就排除了凭据）。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  static const int _version = 1;

  /// A1：写系统「下载」目录的原生通道（MainActivity 里 MediaStore.Downloads）
  static const MethodChannel _saveCh = MethodChannel('yiqikan/save');

  AppDatabase get _db => ref.read(appDatabaseProvider);

  String _status = '';
  bool _busy = false;

  void _say(String s) {
    if (!mounted) return;
    setState(() => _status = s);
  }

  // ── 导出 ───────────────────────────────────────────────
  Future<Map<String, Object?>> _collect() async {
    final List<Source> sources = await _db.select(_db.sources).get();
    final List<Favorite> favs = await _db.select(_db.favorites).get();
    final List<History> his = await _db.select(_db.historyTable).get();
    final List<Room> rooms = await _db.select(_db.rooms).get();
    final List<Account> accs = await _db.select(_db.accounts).get();
    final Prefs prefs = await Prefs.open();

    // 逐键按原样取值：不能拿 getString 去探类型，缓存里存 double 时会抛
    // `'double' is not a subtype of type 'String?' in type cast`。
    final Map<String, Object?> settings = <String, Object?>{};
    for (final String k in PrefKeys.all) {
      final Object? v = prefs.getAny(k);
      if (v != null) settings[k] = v;
    }

    return <String, Object?>{
      'app': 'yiqikan',
      'version': _version,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'sources': <Object?>[
        for (final Source s in sources)
          <String, Object?>{
            'id': s.id,
            'name': s.name,
            'kind': s.kind,
            'apiUrl': s.apiUrl,
            'baseUrl': s.baseUrl,
            'username': s.username,
            'enabled': s.enabled,
            'priority': s.priority,
            'health': s.health,
            'config': s.config,
            'createdAt': s.createdAt,
          },
      ],
      'favorites': <Object?>[
        for (final Favorite f in favs)
          <String, Object?>{
            'id': f.id,
            'title': f.title,
            'url': f.url,
            'sourceKind': f.sourceKind,
            'sourceId': f.sourceId,
            'poster': f.poster,
            'tag': f.tag,
            'note': f.note,
            'addedAt': f.addedAt,
          },
      ],
      'history': <Object?>[
        for (final History h in his)
          <String, Object?>{
            'id': h.id,
            'title': h.title,
            'url': h.url,
            'sourceKind': h.sourceKind,
            'sourceId': h.sourceId,
            'poster': h.poster,
            'position': h.position,
            'duration': h.duration,
            'watchedSeconds': h.watchedSeconds,
            'episodeIndex': h.episodeIndex,
            'seriesId': h.seriesId,
            'watchedAt': h.watchedAt,
            'createdAt': h.createdAt,
          },
      ],
      // 房间只留「怎么进」，不留密码哈希与成员
      'rooms': <Object?>[
        for (final Room r in rooms)
          <String, Object?>{
            'id': r.id,
            'code': r.code,
            'name': r.name,
            'mode': r.mode,
            'joinUrl': r.joinUrl,
            'hostName': r.hostName,
            'memberCount': r.memberCount,
            'lastJoinedAt': r.lastJoinedAt,
            'createdAt': r.createdAt,
          },
      ],
      // 账号只留身份，不留 cookie / token
      'accounts': <Object?>[
        for (final Account a in accs)
          <String, Object?>{
            'kind': a.kind,
            'displayName': a.displayName,
            'username': a.username,
          },
      ],
      'settings': settings,
    };
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final Map<String, Object?> data = await _collect();
      final String body =
          const JsonEncoder.withIndent('  ').convert(data);
      final DateTime now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final String name = 'yiqikan_backup_'
          '${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}.json';
      final int ns = (data['sources'] as List<Object?>).length;
      final int nf = (data['favorites'] as List<Object?>).length;
      final int nh = (data['history'] as List<Object?>).length;

      // 1) 首选：原生 MediaStore 写系统「下载」，用户在文件管理器里能直接看到
      String? path = await _saveToDownloads(name, body);
      int size = utf8.encode(body).length;
      String where = '下载';

      // 2) 回落：让用户自己选位置（SAF）
      if (path == null) {
        final Uri? picked = await FilePicker.saveFile(
          dialogTitle: '保存备份文件',
          fileName: name,
          bytes: Uint8List.fromList(utf8.encode(body)),
          mimeType: 'application/json',
        );
        final String? pickedPath = picked?.toString();
        if (pickedPath != null && pickedPath.isNotEmpty) {
          path = pickedPath;
          size = utf8.encode(body).length;
          where = '你选的位置';
        }
      }

      // 3) 两条都不成：退回应用私有目录（至少不丢数据，用户看不见）
      if (path == null) {
        final Directory dir = await getApplicationDocumentsDirectory();
        final File f = File('${dir.path}/$name');
        await f.writeAsString(body, flush: true);
        path = f.path;
        size = await f.length();
        where = '应用私有目录（文件管理器看不到）';
      }

      debugPrint('[YQK-BACKUP] export path=$path size=$size '
          'sources=$ns favorites=$nf history=$nh');
      _say('已导出到 $path\n'
          '$size B · 源 $ns / 收藏 $nf / 历史 $nh\n'
          '可在文件管理器里找到（$where）');
    } on Object catch (e) {
      debugPrint('[YQK-BACKUP] export fail $e');
      _say('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 走 MainActivity 的 `yiqikan/save` 通道写 MediaStore.Downloads。
  /// 失败/低版本返回 null，由调用方回落。
  Future<String?> _saveToDownloads(String name, String body) async {
    try {
      final String? p = await _saveCh.invokeMethod<String>(
        'saveDownloads',
        <String, Object?>{'fileName': name, 'content': body},
      );
      debugPrint('[YQK-BACKUP] save channel path=$p'
          ' bytes=${utf8.encode(body).length}');
      return (p == null || p.isEmpty) ? null : p;
    } on PlatformException catch (e) {
      debugPrint('[YQK-BACKUP] save channel fail ${e.code} ${e.message}');
      return null;
    } on MissingPluginException catch (e) {
      debugPrint('[YQK-BACKUP] save channel missing $e');
      return null;
    }
  }

  // ── 导入 ───────────────────────────────────────────────
  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final List<PlatformFile> picked = await FilePicker.pickFiles(
        dialogTitle: '选备份文件',
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
      if (picked.isEmpty) {
        debugPrint('[YQK-BACKUP] import cancel');
        return;
      }
      final PlatformFile pf = picked.first;
      final String text = await File(pf.path ?? '').readAsString();
      await _importText(text, from: pf.name);
    } on Object catch (e) {
      debugPrint('[YQK-BACKUP] import fail $e');
      _say('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 从「下载」目录里读最近一份 MediaStore 备份（系统选择器在这台 ROM 上不返回路径）。
  Future<void> _importFromDownloads() async {
    setState(() => _busy = true);
    try {
      final Map<Object?, Object?>? got =
          await _saveCh.invokeMethod<Map<Object?, Object?>>('readLatestDownload');
      if (got == null) {
        _say('下载目录里没有备份文件');
        return;
      }
      final String name = (got['name'] as String?) ?? '备份';
      final String text = (got['content'] as String?) ?? '';
      debugPrint('[YQK-BACKUP] read download name=$name chars=${text.length}');
      await _importText(text, from: name);
    } on PlatformException catch (e) {
      debugPrint('[YQK-BACKUP] read download fail ${e.code} ${e.message}');
      _say('读下载目录失败：${e.message ?? e.code}');
    } on Object catch (e) {
      debugPrint('[YQK-BACKUP] read download fail $e');
      _say('读下载目录失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 共用：解析 + 预览确认 + 合并。
  Future<void> _importText(String text, {required String from}) async {
    final Object? raw = jsonDecode(text);
    if (raw is! Map<String, Object?>) {
      _say('不是合法的备份文件（顶层不是对象）');
      return;
    }
    if (raw['app'] != 'yiqikan') {
      _say('不是本 App 的备份（app=${raw['app']}）');
      return;
    }
    final int ver = (raw['version'] as num?)?.toInt() ?? 0;
    if (ver > _version) {
      _say('备份版本 $ver 比当前 App 支持的 $_version 新，先升级 App');
      return;
    }
    final List<Object?> srcs = (raw['sources'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> favs = (raw['favorites'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> his = (raw['history'] as List<Object?>?) ?? const <Object?>[];
    final Map<String, Object?> settings =
        (raw['settings'] as Map<String, Object?>?) ?? const <String, Object?>{};

    debugPrint('[YQK-BACKUP] import preview file=$from src=${srcs.length} '
        'fav=${favs.length} his=${his.length} set=${settings.length}');

    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: Text('来自 $from\n\n'
            '将导入 ${srcs.length} 个源 / ${favs.length} 条收藏 / '
            '${his.length} 条历史 / ${settings.length} 项设置。\n\n'
            '只补不覆盖：已有的条目会跳过。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('导入')),
        ],
      ),
    );
    if (go != true) return;

    // 合并逻辑在 BackupMerger 里（可单测）：只补不覆盖。
    final Map<String, Map<String, int>> rep = await BackupMerger.merge(_db, raw);
    final Map<String, int> added = rep['added']!;
    final Map<String, int> skipped = rep['skipped']!;
    debugPrint('[YQK-BACKUP] import 新增 src=${added['src']} fav=${added['fav']} '
        'his=${added['his']} set=${added['set']} | '
        '跳过 src=${skipped['src']} fav=${skipped['fav']} his=${skipped['his']} '
        'set=${skipped['set']}');
    _say('导入完成（$from）：新增 ${added['src']} 源 / ${added['fav']} 收藏 / '
        '${added['his']} 历史 / ${added['set']} 设置\n'
        '跳过 ${skipped['src']} / ${skipped['fav']} / ${skipped['his']} / '
        '${skipped['set']}（已存在）');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.page),
        children: <Widget>[
          Text(
            '导出一份 JSON（源 / 收藏 / 历史 / 房间入口 / 账号身份 / 设置）。\n'
            '不含 cookie、token、房间密码、成员列表。',
            style: TextStyle(color: AppColors.textSub, height: 1.6),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: _busy ? null : () => unawaited(_export()),
            icon: const Icon(Icons.upload_file),
            label: const Text('导出备份'),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_import()),
            icon: const Icon(Icons.download_outlined),
            label: const Text('从文件导入'),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_importFromDownloads()),
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text('从「下载」导入最近一份'),
          ),
          const SizedBox(height: AppSpace.lg),
          if (_busy) const LinearProgressIndicator(),
          if (_status.isNotEmpty)
            SelectableText(_status,
                style: TextStyle(color: AppColors.textSub, height: 1.5)),
        ],
      ),
    );
  }
}