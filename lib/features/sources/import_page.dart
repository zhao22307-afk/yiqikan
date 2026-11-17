import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/sources/tvbox_config.dart';
import '../../data/sources/tvbox_importer.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import 'source_add_page.dart';

/// P1c 导入片源配置：贴地址 / 粘 JSON / 单个源。
///
/// 只吃 TVBox 那一类配置（有 `sites` 数组）。Kazumi 的规则要解释器，这里只提示。
class SourceImportPage extends ConsumerStatefulWidget {
  const SourceImportPage({super.key});

  @override
  ConsumerState<SourceImportPage> createState() => _SourceImportPageState();
}

class _SourceImportPageState extends ConsumerState<SourceImportPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  late final TextEditingController _url =
      TextEditingController(text: 'https://raw.githubusercontent.com/qist/tvbox/master/dianshi.json');
  late final TextEditingController _json = TextEditingController();

  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _tab.dispose();
    _url.dispose();
    _json.dispose();
    super.dispose();
  }

  // ---------------- Tab1 / Tab2 共用 ----------------

  Future<void> _importFromUrl() async {
    final String url = _url.text.trim();
    if (url.isEmpty) {
      _toast('先填配置地址');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final Dio dio = Dio(BaseOptions(
        connectTimeout: kHttpConnectTimeout,
        receiveTimeout: kHttpReadTimeout,
        responseType: ResponseType.plain,
        validateStatus: (int? s) => s != null && s < 500,
      ));
      final Response<dynamic> r = await dio.get<dynamic>(url);
      final int code = r.statusCode ?? 0;
      if (code >= 400 || r.data == null) {
        _toast('拉配置失败：HTTP $code');
        return;
      }
      await _importRaw(r.data.toString(), 'from-url');
    } on Object catch (e) {
      _toast('拉配置失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    // 只打印最终数字，便于验收 grep
    debugPrint('[YQK-TVBOX] import from-url url=$url');
  }

  Future<void> _importFromPaste() async {
    final String raw = _json.text.trim();
    if (raw.isEmpty) {
      _toast('先把 JSON 粘进来');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _importRaw(raw, 'from-paste');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 解析 → 确认框（必须显示「可用 X / 总 Y」）→ 导入。
  Future<void> _importRaw(String raw, String label) async {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      _toast('这段不是合法 JSON');
      return;
    }
    if (decoded is! Map) {
      _toast('这段不是 JSON 对象');
      return;
    }
    final Map<String, dynamic> map = decoded.cast<String, dynamic>();
    final Object? sites = map['sites'];
    if (sites is! List) {
      // Kazumi 的配置长这样：name / version / api 在顶层，没有 sites
      if (map.containsKey('api') || map.containsKey('version')) {
        _toast('Kazumi 规则需要规则引擎，下一版支持');
      } else {
        _toast('没找到 sites 数组，这不像 TVBox 配置');
      }
      return;
    }

    final List<TvboxSite> parsed = TvboxConfig.parse(raw);
    final int total = parsed.length;
    final int usable = parsed.where(TvboxConfig.usable).length;
    debugPrint('[YQK-TVBOX] preview $label total=$total usable=$usable');

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: Text('找到 $total 个源，可用 $usable 个，将导入 $usable 个，继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (ok != true) {
      debugPrint('[YQK-TVBOX] import $label cancelled');
      return;
    }

    final TvboxImporter importer =
        TvboxImporter(service: ref.read(sourceServiceProvider));
    final int added = await importer.importFrom(raw, label: label);
    if (!mounted) return;
    setState(() {
      _message = '$label 导入完成：新增 $added 个（总 $total，可用 $usable）';
    });
    _toast('新增 $added 个源');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入片源'),
        bottom: TabBar(
          controller: _tab,
          tabs: const <Widget>[
            Tab(text: '贴配置地址'),
            Tab(text: '粘贴 JSON'),
            Tab(text: '单个源'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: <Widget>[
          _urlTab(),
          _pasteTab(),
          // 第三个 tab 直接复用「添加片源」那张表单，不再写一份
          const SourceAddPage(),
        ],
      ),
    );
  }

  Widget _urlTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.page),
      children: <Widget>[
        Text('配置地址', style: AppText.label.copyWith(color: AppColors.textSub)),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'https://xxx/tvbox.json'),
        ),
        const SizedBox(height: AppSpace.lg),
        FilledButton.icon(
          onPressed: _busy ? null : _importFromUrl,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_download_outlined),
          label: const Text('导入'),
        ),
        const SizedBox(height: AppSpace.md),
        if (_message != null)
          Text(_message!, style: AppText.sub.copyWith(color: AppColors.textSub)),
        const SizedBox(height: AppSpace.md),
        Text(
          '只认 TVBox 配置（顶层有 sites 数组）。导入前会显示「可用 X / 总 Y」让你确认，'
          '重复导入同一个配置不会产生重复源。',
          style: AppText.sub.copyWith(color: AppColors.textDim),
        ),
      ],
    );
  }

  Widget _pasteTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.page),
      children: <Widget>[
        Text('配置 JSON', style: AppText.label.copyWith(color: AppColors.textSub)),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: _json,
          minLines: 8,
          maxLines: 16,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '把配置 JSON 粘进来'),
        ),
        const SizedBox(height: AppSpace.lg),
        FilledButton.icon(
          onPressed: _busy ? null : _importFromPaste,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.content_paste_go),
          label: const Text('导入'),
        ),
        const SizedBox(height: AppSpace.md),
        if (_message != null)
          Text(_message!, style: AppText.sub.copyWith(color: AppColors.textSub)),
      ],
    );
  }
}
