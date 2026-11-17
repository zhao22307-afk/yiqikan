/// P10/P11 网盘：账号列表（已接的几家 + 添加账号）。
///
/// 五态齐全：加载 / 空（引导去添加）/ 错误（人话 + 重试）/ 有数据 / 局部失败（某行标红）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/failure_text.dart';
import '../../data/db/app_database.dart';
import '../../data/netdisk/netdisk_account_store.dart';
import '../../data/netdisk/netdisk_adapter.dart';
import '../../data/netdisk/share_link.dart';
import '../../providers/app_providers.dart';
import '../../routing/routes.dart';
import '../../theme/app_theme.dart';

class NetdiskPage extends ConsumerStatefulWidget {
  const NetdiskPage({super.key});

  @override
  ConsumerState<NetdiskPage> createState() => _NetdiskPageState();
}

class _NetdiskPageState extends ConsumerState<NetdiskPage> {
  List<Account>? _rows;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final NetdiskAccountStore store = ref.read(netdiskStoreProvider);
      final List<Account> rows = await store.list();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = FailureText.lineOf(e);
        _loading = false;
      });
    }
  }

  Future<void> _remove(Account a) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('删掉这个账号？'),
        content: Text('只会删本机保存的凭据，"${a.displayName}" 里的文件不会被动。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('算了')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删掉')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(netdiskStoreProvider).remove(a);
    await _load();
  }

  /// 绑定分享：粘贴整段分享文案也行，解析出「哪家 + 分享 id + 提取码」再写进 extra
  Future<void> _bindShare(Account a) async {
    final TextEditingController input = TextEditingController();
    final ShareLink? current = NetdiskAccountStore.bindingOf(a);
    if (current != null) input.text = current.rawUrl.isEmpty ? current.shareId : current.rawUrl;
    ShareLink? parsed = current;
    bool bad = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, void Function(void Function()) setDialog) {
          void doParse() {
            parsed = parseShareLink(input.text);
            bad = parsed == null;
            setDialog(() {});
          }

          return AlertDialog(
            title: const Text('绑定分享链接'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '把分享链接粘进来就行，整段分享文案也能识别。',
                  style: AppText.sub,
                ),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: input,
                  maxLines: 3,
                  style: AppText.label,
                  decoration: const InputDecoration(
                    hintText: 'https://pan.quark.cn/s/xxxx 或整段分享文案',
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                if (parsed != null) ...<Widget>[
                  Text(
                    '识别到：${parsed!.display}',
                    style: AppText.sub.copyWith(color: AppColors.success),
                  ),
                  if (parsed!.kind.prefValue != a.kind)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '注意：这条是 ${parsed!.kind.label} 的链接，当前账号是 '
                        '${NetdiskKind.parse(a.kind).label}，绑上去也打不开',
                        style: AppText.label.copyWith(color: AppColors.warn),
                      ),
                    ),
                ] else if (bad)
                  Text(
                    '没识别出分享链接，支持：夸克 / 115 / 123 / 天翼',
                    style: AppText.sub.copyWith(color: AppColors.danger),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              TextButton(onPressed: doParse, child: const Text('识别')),
              FilledButton(
                onPressed: parsed == null ? null : () => Navigator.pop(c, true),
                child: const Text('绑定'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || parsed == null) return;
    await ref.read(netdiskStoreProvider).bindShare(a, parsed!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '已绑定 ${parsed!.kind.label} 的分享：${parsed!.shareId}（M6-2 起在浏览页直接生效）',
      ),
      behavior: SnackBarBehavior.floating,
    ));
    await _load();
  }

  Future<void> _revalidate(Account a) async {    final bool ok = await ref.read(netdiskStoreProvider).revalidate(a);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '${a.displayName} 连得上' : '${a.displayName} 连不上，可能要重新登录'),
      behavior: SnackBarBehavior.floating,
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网盘'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            tooltip: '添加账号',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final bool? added = await context.push<bool>(Routes.netdiskAdd);
              if (added == true) await _load();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_off, size: 40, color: AppColors.textDim),
              const SizedBox(height: AppSpace.sm),
              Text(err, textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppColors.textSub)),
              const SizedBox(height: AppSpace.md),
              OutlinedButton(onPressed: _load, child: const Text('再试一次')),
            ],
          ),
        ),
      );
    }
    final List<Account> rows = _rows ?? const <Account>[];
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_queue, size: 40, color: AppColors.textDim),
              const SizedBox(height: AppSpace.sm),
              Text('还没接网盘', style: AppText.section),
              const SizedBox(height: AppSpace.xs),
              Text(
                '接上 WebDAV / AList / Emby，就能在这里直接看自己存的东西',
                textAlign: TextAlign.center,
                style: AppText.sub,
              ),
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                onPressed: () async {
                  final bool? added = await context.push<bool>(Routes.netdiskAdd);
                  if (added == true) await _load();
                },
                icon: const Icon(Icons.add),
                label: const Text('添加第一个账号'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpace.page),
        itemCount: rows.length,
        separatorBuilder: (BuildContext _, int _) => const SizedBox(height: AppSpace.sm),
        itemBuilder: (BuildContext c, int i) {
          final Account a = rows[i];
          final bool bad = a.status != 'ok';
          return Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => context.push(
                '${Routes.netdiskBrowse}?id=${Uri.encodeComponent(a.id)}&name=${Uri.encodeComponent(a.displayName)}',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.md,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.cloud_outlined,
                      color: bad ? AppColors.danger : AppColors.primary,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(a.displayName, style: AppText.card),
                          const SizedBox(height: 2),
                          Text(
                            '${NetdiskKind.parse(a.kind).label} · ${NetdiskAccountStore.statusText(a)}',
                            style: AppText.sub.copyWith(
                              color: bad ? AppColors.danger : AppColors.textSub,
                            ),
                          ),
                          // 分享已经写进 accounts.extra，但四家的 list() 还没消费它（M6-2 才接），
                          // 这里明说一句，免得以为「绑了却看不到内容」是 bug。
                          if (NetdiskAccountStore.bindingOf(a) != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              '已绑定分享：${NetdiskAccountStore.bindingOf(a)!.display} · M6-2 生效',
                              style: AppText.sub.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '绑定分享',
                      icon: const Icon(Icons.link, size: 20),
                      onPressed: () => _bindShare(a),
                    ),
                    IconButton(
                      tooltip: '重新验证',
                      icon: const Icon(Icons.wifi_tethering, size: 20),
                      onPressed: () => _revalidate(a),
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _remove(a),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}