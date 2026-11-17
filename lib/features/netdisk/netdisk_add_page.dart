/// 添加网盘账号：选平台 → 选登录方式（扫码 / 手动 Cookie / 账号密码）→ 验证 → 存 SecureStore。
///
/// 第二段先把四家的登录入口搭起来：二维码能出图、Cookie 能粘、能选平台；
/// 真正的「扫完能不能登录」等真实凭据到手再验（不许用假数据假装跑通）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/failure_text.dart';
import '../../data/netdisk/netdisk_account_store.dart';
import '../../data/netdisk/netdisk_adapter.dart';
import '../../data/netdisk/quark_adapter.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';

/// 三种登录方式，按平台给不同的可选项
enum NetdiskLoginMode {
  qr('扫码登录'),
  cookie('手动 Cookie'),
  password('账号密码');

  const NetdiskLoginMode(this.label);

  final String label;

  /// 谁能扫码：夸克和 115 有扫码接口；123 走账号密码；天翼只有 Cookie
  static List<NetdiskLoginMode> of(NetdiskKind kind) {
    switch (kind) {
      case NetdiskKind.quark:
      case NetdiskKind.pan115:
        return <NetdiskLoginMode>[NetdiskLoginMode.qr, NetdiskLoginMode.cookie];
      case NetdiskKind.pan123:
        return <NetdiskLoginMode>[
          NetdiskLoginMode.password,
          NetdiskLoginMode.cookie,
        ];
      case NetdiskKind.tianyi:
        return <NetdiskLoginMode>[NetdiskLoginMode.cookie];
      case NetdiskKind.webdav:
      case NetdiskKind.alist:
      case NetdiskKind.emby:
        return <NetdiskLoginMode>[
          NetdiskLoginMode.password,
          NetdiskLoginMode.cookie,
        ];
    }
  }
}

class NetdiskAddPage extends ConsumerStatefulWidget {
  const NetdiskAddPage({super.key});

  @override
  ConsumerState<NetdiskAddPage> createState() => _NetdiskAddPageState();
}

class _NetdiskAddPageState extends ConsumerState<NetdiskAddPage> {
  NetdiskKind _kind = NetdiskKind.webdav;
  NetdiskLoginMode _mode = NetdiskLoginMode.password;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _cookie = TextEditingController();

  bool _busy = false;
  String? _msg;
  bool _msgBad = false;

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _user.dispose();
    _pass.dispose();
    _cookie.dispose();
    super.dispose();
  }

  bool get _isLocal => _kind == NetdiskKind.webdav ||
      _kind == NetdiskKind.alist ||
      _kind == NetdiskKind.emby;

  String get _endpointHint {
    switch (_kind) {
      case NetdiskKind.webdav:
        return 'https://nas.example.com/dav';
      case NetdiskKind.alist:
        return 'http://192.168.1.10:5244';
      case NetdiskKind.emby:
        return 'http://192.168.1.10:8096';
      default:
        return '';
    }
  }

  void _pickKind(NetdiskKind k) {
    setState(() {
      _kind = k;
      final List<NetdiskLoginMode> modes = NetdiskLoginMode.of(k);
      if (!modes.contains(_mode)) _mode = modes.first;
      _msg = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final String secret = _mode == NetdiskLoginMode.cookie
          ? _cookie.text.trim()
          : _mode == NetdiskLoginMode.qr
              ? _cookie.text.trim()
              : '';
      final NetdiskDraft draft = NetdiskDraft(
        kind: _kind,
        displayName: _name.text,
        endpoint: _endpoint.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
        // 网盘类（夸克/115/123/天翼）把 cookie/token 统一放 token 字段
        token: secret,
      );
      await ref.read(netdiskStoreProvider).add(draft);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = e is AppException ? e.display : FailureText.lineOf(e);
        _msgBad = true;
        _busy = false;
      });
    }
  }

  /// 扫码弹窗：先拿二维码内容，再轮询状态（夸克的流程；115 等真凭据时再接）
  Future<void> _showQr() async {
    if (_kind != NetdiskKind.quark) {
      setState(() {
        _msg = '${_kind.label} 的扫码要等真机登录接口接通，先用手动 Cookie';
        _msgBad = true;
      });
      return;
    }
    final QuarkAdapter probe = QuarkAdapter(
      account: NetdiskAccountInfo(kind: _kind, displayName: _kind.label),
      cookie: '',
      store: ref.read(netdiskStoreProvider).secure,
    );
    final QuarkQrSession session;
    try {
      session = await probe.qrToken();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = e is AppException ? e.display : FailureText.lineOf(e);
        _msgBad = true;
      });
      return;
    }
    if (!mounted) return;
    // 二维码 token 一般 5 分钟失效；过期就自己重开一张，不把「等扫码…」一直挂着
    var current = session;
    var status = '拿手机上的夸克 App 扫这个码（5 分钟内有效）';
    var refreshes = 0;
    Timer? timer;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setDialog) {
          timer ??= Timer.periodic(const Duration(seconds: 3), (Timer t) async {
            try {
              final ({QuarkQrState state, String ticket}) r = await probe.qrPoll(current);
              switch (r.state) {
                case QuarkQrState.confirmed:
                  final String cookie = await probe.cookieFromTicket(r.ticket);
                  t.cancel();
                  if (mounted) setState(() => _cookie.text = cookie);
                  setDialog(() => status = '扫码成功，已经把 Cookie 填进来了');
                case QuarkQrState.scanned:
                  setDialog(() => status = QuarkQrState.scanned.text);
                case QuarkQrState.waiting:
                  setDialog(() => status = QuarkQrState.waiting.text);
                case QuarkQrState.expired:
                  if (refreshes >= 3) {
                    t.cancel();
                    setDialog(() => status = '二维码连着过期三次，关掉重开一次');
                    break;
                  }
                  refreshes++;
                  debugPrint('[YQK-QUARK] qr expired n=$refreshes/3 -> refreshing');
                  final QuarkQrSession fresh = await probe.qrToken();
                  current = fresh;
                  setDialog(() => status = QuarkQrState.expired.text);
              }
            } on Object catch (e) {
              setDialog(() => status = e is AppException ? e.display : '轮询失败，稍后再试');
              t.cancel();
            }
          });
          return AlertDialog(
            title: const Text('扫码登录夸克'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: current.qrContent,
                    size: 200,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(status, style: AppText.sub, textAlign: TextAlign.center),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  timer?.cancel();
                  Navigator.of(ctx).pop();
                },
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
    timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final bool alist = _kind == NetdiskKind.alist;
    final List<NetdiskLoginMode> modes = NetdiskLoginMode.of(_kind);
    return Scaffold(
      appBar: AppBar(title: const Text('添加网盘')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.page),
        children: <Widget>[
          Text('平台', style: AppText.section),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: NetdiskKind.values.map((NetdiskKind k) {
              return ChoiceChip(
                label: Text(k.label),
                selected: _kind == k,
                onSelected: (bool _) => _pickKind(k),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('登录方式', style: AppText.section),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            children: modes
                .map((NetdiskLoginMode m) => ChoiceChip(
                      label: Text(m.label),
                      selected: _mode == m,
                      onSelected: (bool _) => setState(() => _mode = m),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('备注名', style: AppText.section),
          const SizedBox(height: AppSpace.xs),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '比如「家里的 NAS」'),
          ),
          if (_isLocal) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            Text(alist ? 'AList 地址' : '服务地址', style: AppText.section),
            const SizedBox(height: AppSpace.xs),
            TextField(
              controller: _endpoint,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(hintText: _endpointHint),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          if (_mode == NetdiskLoginMode.qr) ...<Widget>[
            OutlinedButton.icon(
              onPressed: _showQr,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('生成二维码'),
            ),
            if (_cookie.text.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.xs),
              Text('已经拿到 Cookie，直接保存即可', style: AppText.label),
            ],
          ] else if (_mode == NetdiskLoginMode.cookie) ...<Widget>[
            Text('Cookie', style: AppText.section),
            const SizedBox(height: AppSpace.xs),
            TextField(
              controller: _cookie,
              maxLines: 4,
              style: AppText.label,
              decoration: const InputDecoration(
                hintText: '把浏览器里这一站点的 Cookie 整段粘进来（形如 a=1; b=2）',
              ),
            ),
          ] else ...<Widget>[
            Text(alist ? 'Token' : '用户名', style: AppText.section),
            const SizedBox(height: AppSpace.xs),
            TextField(
              controller: _user,
              decoration: InputDecoration(hintText: alist ? 'AList 后台 → 设置 → API 的 token' : '账号'),
            ),
            if (!alist) ...<Widget>[
              const SizedBox(height: AppSpace.md),
              Text('密码', style: AppText.section),
              const SizedBox(height: AppSpace.xs),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(hintText: '只存在本机加密存储里'),
              ),
            ],
          ],
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('验证并保存'),
          ),
          if (_msg != null) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            Text(
              _msg!,
              style: AppText.sub.copyWith(
                color: _msgBad ? AppColors.danger : AppColors.success,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          Text(
            '账号只存在这台手机里，凭据走系统加密存储；地址和用户名会写进本地数据库，方便下次直接用。',
            style: AppText.label.copyWith(color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}