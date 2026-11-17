import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/app_colors.dart';
import '../../core/error/error_log.dart';
import '../../core/error/probe_page.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/translate/translator_store.dart';
import '../../domain/translator.dart';
import '../../core/update/apk_installer.dart';
import '../../core/update/update_checker.dart';
import '../../core/constants.dart';
import '../../data/local/prefs.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/room/channel.dart';
import '../onboarding/onboarding_overlay.dart';
import '../sources/sources_page.dart';
import '../dynamic/dynamic_page.dart';
import 'backup_page.dart';
import 'diagnose_page.dart';
import 'permission_page.dart';
import 'power_page.dart';
import 'storage_page.dart';

/// 设置页（目前只有 D26 的房间通道策略）。
///
/// 为什么单独开一页：策略要在**进房之前**就能改，放在播放页的高级面板里
/// 得先播一次才够得着，所以从首页齿轮进来。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ChannelMode _mode = ChannelMode.auto;
  ThemeModePref _themePref = ThemeModePref.system;
  double _fontScale = 1.0;
  LocalePref _localePref = LocalePref.system;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Prefs prefs = await Prefs.open();
    final ChannelMode m =
        channelModeFromPref(prefs.getString(PrefKeys.channelMode));
    final ThemeModePref t =
        ThemeController.prefFromName(prefs.getString(PrefKeys.themeMode));
    final double f = prefs.getDouble(PrefKeys.fontScale) ?? 1.0;
    final LocalePref lp =
        ThemeController.localeFromName(prefs.getString(PrefKeys.locale));
    if (!mounted) return;
    setState(() {
      _mode = m;
      _themePref = t;
      _fontScale = f;
      _localePref = lp;
      _loading = false;
    });
  }

  Future<void> _pick(ChannelMode m) async {
    setState(() => _mode = m);
    final Prefs prefs = await Prefs.open();
    await prefs.setString(PrefKeys.channelMode, channelModeToPref(m));
    debugPrint('[YQK-CH] mode saved mode=${channelModeToPref(m)}');
  }

  /// 主题：写 prefs + 通知根部重建（立即生效，不等重启）。
  Future<void> _pickTheme(ThemeModePref t) async {
    setState(() => _themePref = t);
    final Prefs prefs = await Prefs.open();
    await prefs.setString(PrefKeys.themeMode, ThemeController.prefName(t));
    ThemeController.setPref(t);
    debugPrint('[YQK-THEME] pick=${ThemeController.prefName(t)} saved');
  }

  /// 字号：0.9 / 1.0 / 1.15，写 prefs + 立即重建。
  Future<void> _pickFont(double s) async {
    setState(() => _fontScale = s);
    final Prefs prefs = await Prefs.open();
    await prefs.setDouble(PrefKeys.fontScale, s);
    ThemeController.setFontScale(s);
    debugPrint('[YQK-FONT] pick=$s saved');
  }

  /// G1：语言三档（跟系统 / 中文 / English），写 prefs + 根部重建。
  Future<void> _pickLocale(LocalePref p) async {
    setState(() => _localePref = p);
    final Prefs prefs = await Prefs.open();
    await prefs.setString(PrefKeys.locale, ThemeController.localeName(p));
    ThemeController.setLocalePref(p);
    debugPrint('[YQK-L10N] pick=${ThemeController.localeName(p)} saved '
        'effective=${ThemeController.effectiveLocale?.toLanguageTag() ?? 'system'}');
  }

  // ── G8 更新检查 ────────────────────────────────────────

  Future<void> _checkUpdate() async {
    final Prefs prefs = await Prefs.open();
    final String saved = prefs.getString(PrefKeys.updateFeedUrl) ?? '';
    final TextEditingController ctrl = TextEditingController(text: saved);
    if (!mounted) return;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('检查更新'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('当前版本 $kAppVersion',
                style: TextStyle(color: AppColors.textSub, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '更新源 JSON 地址',
                hintText: 'http://10.0.0.2:9000/update.json',
              ),
            ),
            const SizedBox(height: 8),
            Text('留空 = 不检查；自建源只要一个静态 JSON',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('检查'),
          ),
        ],
      ),
    );
    final String feed = ctrl.text.trim();
    ctrl.dispose();
    if (go != true) return;
    await prefs.setString(PrefKeys.updateFeedUrl, feed);
    debugPrint('[YQK-UPD] feed saved url=${feed.isEmpty ? '(empty)' : feed}');
    if (feed.isEmpty) {
      _toast('还没配更新源');
      return;
    }
    final UpdateInfo? info =
        await UpdateChecker().check(feed, kAppVersion);
    if (!mounted) return;
    if (info == null) {
      debugPrint('[YQK-UPD] no update current=$kAppVersion');
      _toast('已是最新版本（$kAppVersion）');
      return;
    }
    await _offerUpdate(info);
  }

  Future<void> _offerUpdate(UpdateInfo info) async {
    if (!mounted) return;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('有新版本 ${info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('当前 $kAppVersion → ${info.version}',
                style: TextStyle(color: AppColors.textSub, fontSize: 13)),
            const SizedBox(height: 8),
            Text('大小 ${UpdateInfo.sizeText(info.size)}'),
            if (info.notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(info.notes),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('以后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('下载并安装'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await _downloadAndInstall(info);
  }

  Future<void> _downloadAndInstall(UpdateInfo info) async {
    final Directory dir = await getApplicationSupportDirectory();
    final File apk = File('${dir.path}/update/app-release.apk');
    final ValueNotifier<double> p = ValueNotifier<double>(0);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('下载中…'),
        content: ValueListenableBuilder<double>(
          valueListenable: p,
          builder: (BuildContext _, double v, Widget? __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: v <= 0 ? null : v),
              const SizedBox(height: 8),
              Text('${(v * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );
    String err = '';
    try {
      final File f = await UpdateChecker().download(
        info,
        apk.path,
        onProgress: (int got, int total) {
          if (total > 0) p.value = got / total;
        },
      );
      debugPrint('[YQK-UPD] ready to install ${f.path}');
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      final bool can = await ApkInstaller.canInstall();
      if (!can) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('需要「安装未知应用」权限'),
            content: const Text('系统要求你手动允许一次：设置 → 安装未知应用 → 一起看。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  unawaited(ApkInstaller.openUnknownSources());
                },
                child: const Text('去设置'),
              ),
            ],
          ),
        );
        return;
      }
      final String r = await ApkInstaller.install(apk);
      if (r != 'ok') err = r;
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      err = '$e';
      debugPrint('[YQK-UPD] install flow fail $e');
    } finally {
      p.dispose();
    }
    if (!mounted) return;
    if (err.isNotEmpty) {
      _toast('更新失败：$err');
    } else {
      _toast('已交给系统安装器');
    }
  }

  /// G5：清掉标记 → 首页会立刻重新弹三步引导
  Future<void> _replayGuide() async {
    final Prefs prefs = await Prefs.open();
    await prefs.setBool(PrefKeys.onboardingDone, false);
    debugPrint('[YQK-GUIDE] replay requested (done=false)');
    OnboardingGate.replay();
    _toast('回首页会重新显示引导');
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  /// H2 翻译服务配置：端点 + 密钥 + 测试。密钥只进 SecureStore，不进 prefs。
  Future<void> _openTranslate() async {
    final TranslatorStore store = TranslatorStore();
    final String ep0 = await store.endpoint();
    final String sk0 = await store.secret();
    if (!mounted) return;
    final TextEditingController epCtl = TextEditingController(text: ep0);
    final TextEditingController skCtl = TextEditingController(text: sk0);
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('翻译服务'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: epCtl,
                decoration: const InputDecoration(
                  labelText: '端点（POST JSON）',
                  hintText: 'https://your-server/translate',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: skCtl,
                decoration: const InputDecoration(
                  labelText: '密钥（可空）',
                  hintText: 'Bearer token',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请求体：{"q":"原文","target":"zh"}；响应读 translated。',
                style: TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final HttpTranslator probe =
                  HttpTranslator(endpoint: epCtl.text, key: skCtl.text);
              debugPrint('[YQK-TRANS] test endpoint=${epCtl.text.trim()}');
              final String? r = await probe.selfTest();
              debugPrint('[YQK-TRANS] test result=${r ?? 'null'}');
              _toast(r == null
                  ? '测试失败：端点没响应或返回格式不对'
                  : '测试成功：$r');
            },
            child: const Text('测试'),
          ),
          TextButton(
            onPressed: () async {
              await store.clear();
              if (ctx.mounted) Navigator.of(ctx).pop(false);
              _toast('已清空翻译配置');
            },
            child: const Text('清空'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await store.save(endpoint: epCtl.text, key: skCtl.text);
      debugPrint('[YQK-TRANS] saved endpoint=${epCtl.text.trim()} '
          'key=${skCtl.text.trim().isEmpty ? '(none)' : '***'}');
      _toast('已保存翻译服务');
    }
  }

  @override
  Widget build(BuildContext context) {
    final L t = L.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t.tabSettings)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.page),
              children: <Widget>[
                Text(t.setTheme,
                    style: TextStyle(
                        color: AppColors.textSub,
                        fontSize: 13,
                        letterSpacing: 1)),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: <Widget>[
                    for (final ThemeModePref t in ThemeModePref.values)
                      ChoiceChip(
                        label: Text(switch (t) {
                          ThemeModePref.system => '跟随系统',
                          ThemeModePref.light => '浅色',
                          ThemeModePref.dark => '深色',
                        }),
                        selected: _themePref == t,
                        onSelected: (bool on) {
                          if (!on) return;
                          unawaited(_pickTheme(t));
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Text(t.setFont,
                    style: TextStyle(
                        color: AppColors.textSub,
                        fontSize: 13,
                        letterSpacing: 1)),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  children: <Widget>[
                    for (final double s in <double>[0.9, 1.0, 1.15])
                      ChoiceChip(
                        label: Text('${ThemeController.fontScaleName(s)} '
                            '${s.toStringAsFixed(2)}'),
                        selected: (_fontScale - s).abs() < 0.01,
                        onSelected: (bool on) {
                          if (!on) return;
                          unawaited(_pickFont(s));
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Text(t.setLanguage,
                    style: TextStyle(
                        color: AppColors.textSub,
                        fontSize: 13,
                        letterSpacing: 1)),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: <Widget>[
                    for (final LocalePref p in LocalePref.values)
                      ChoiceChip(
                        label: Text(switch (p) {
                          LocalePref.system => '跟随系统',
                          LocalePref.zh => '中文',
                          LocalePref.en => 'English',
                        }),
                        selected: _localePref == p,
                        onSelected: (bool on) {
                          if (!on) return;
                          unawaited(_pickLocale(p));
                        },
                      ),
                  ],
                ),
                const Divider(height: AppSpace.lg),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sd_storage_outlined,
                      color: AppColors.textSub),
                  title: Text('存储与缓存',
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('看各部分占用、清理缓存',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const StoragePage(),
                    ),
                  ),
                ),
                const Divider(height: AppSpace.lg),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.backup_outlined,
                      color: AppColors.textSub),
                  title: Text(t.setBackup,
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('导出 JSON / 从文件导入（不含凭据）',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const BackupPage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.star_rate_outlined,
                      color: AppColors.textSub),
                  title: Text('片源评分',
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('在片源列表里点星星打分，搜索结果会显示平均分',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const SourcesPage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.battery_saver_outlined,
                      color: AppColors.textSub),
                  title: Text(t.setPower,
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('电池优化白名单 / 锁屏与切后台时的行为',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const PowerPage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.translate_outlined, color: AppColors.textSub),
                  title: Text('翻译服务',
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('自填端点与密钥（不内置任何厂商 Key）',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing:
                      Icon(Icons.chevron_right, color: AppColors.textSub),
                  onTap: () => unawaited(_openTranslate()),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.monitor_heart_outlined,
                      color: AppColors.textSub),
                  title: Text(t.setDiagnose,
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('版本 / 端口 / 通道 / 房间 / 最近错误，一键复制',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const DiagnosePage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.verified_user_outlined,
                      color: AppColors.textSub),
                  title: Text(t.setPermission,
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('通知 / 相册 / 相机 / 麦克风 / 安装未知应用',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const PermissionPage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dashboard_customize_outlined,
                      color: AppColors.textSub),
                  title: Text('活动页（示例）',
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('banner / 卡片 / 按钮 / 提示等 9 种 block',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const DynamicPage(id: 'demo'),
                    ),
                  ),
                ),
                const Divider(height: AppSpace.lg),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_alt,
                      color: AppColors.textSub),
                  title: Text(t.setUpdate,
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('自建更新源（静态 JSON），下载后校验 SHA-256',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => unawaited(_checkUpdate()),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.school_outlined,
                      color: AppColors.textSub),
                  title: Text('重新看一遍引导',
                      style: TextStyle(color: AppColors.text)),
                  subtitle: Text('首页三步高亮引导（搜片 / 我的 / 建房）',
                      style: TextStyle(color: AppColors.textSub)),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSub),
                  onTap: () => unawaited(_replayGuide()),
                ),
                const Divider(height: AppSpace.lg),
                if (kDebugMode) ...<Widget>[
                  Text('开发诊断',
                      style: TextStyle(
                          color: AppColors.textSub,
                          fontSize: 13,
                          letterSpacing: 1)),
                  const SizedBox(height: AppSpace.xs),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bug_report_outlined,
                        color: AppColors.textSub),
                    title: Text('崩溃兜底页（调试）',
                        style: TextStyle(color: AppColors.text)),
                    subtitle: Text('故意抛 build 期异常，看兜底页而不是红屏',
                        style: TextStyle(color: AppColors.textSub)),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) => const BoomPage(),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bolt_outlined, color: AppColors.textSub),
                    title: Text('异步异常（调试）',
                        style: TextStyle(color: AppColors.text)),
                    subtitle: Text('造一条没人捕获的 Future.error',
                        style: TextStyle(color: AppColors.textSub)),
                    onTap: fireAsyncError,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.warning_amber_outlined,
                        color: AppColors.textSub),
                    title: Text('同步异常（调试）',
                        style: TextStyle(color: AppColors.text)),
                    subtitle: Text('catch 住一条同步异常，只进错误环形缓存',
                        style: TextStyle(color: AppColors.textSub)),
                    onTap: () {
                      try {
                        throw StateError('调试用的同步异常（sync）');
                      } on Object catch (e, st) {
                        ErrorLog.add('sync', e, st);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已记一条同步异常')),
                        );
                      }
                    },
                  ),
                  const Divider(height: AppSpace.lg),
                ],
                Text('房间通道',
                    style: TextStyle(
                        color: AppColors.textSub,
                        fontSize: 13,
                        letterSpacing: 1)),
                const SizedBox(height: AppSpace.sm),
                for (final ChannelMode m in ChannelMode.values)
                  RadioListTile<ChannelMode>(
                    value: m,
                    // ignore: deprecated_member_use
                    groupValue: _mode,
                    // ignore: deprecated_member_use
                    onChanged: (ChannelMode? v) {
                      if (v == null) return;
                      unawaited(_pick(v));
                    },
                    title: Text(channelModeLabel(m),
                        style: TextStyle(color: AppColors.text)),
                    subtitle: Text(
                      switch (m) {
                        ChannelMode.auto => '按评分选：局域网优先，通了就用它',
                        ChannelMode.lanOnly => '只用局域网地址，隧道不参与',
                        ChannelMode.forceTunnel => '只用隧道地址；没配隧道就进不去',
                        ChannelMode.ipv6Only => '只用全局 IPv6 地址；对端没有 IPv6 就连不上',
                      },
                      style: TextStyle(color: AppColors.textSub),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: AppSpace.md),
                Text(
                  '改完下一次进房生效（正在看的房间不受影响）。',
                  style: TextStyle(color: AppColors.textSub, height: 1.6),
                ),
              ],
            ),
    );
  }
}