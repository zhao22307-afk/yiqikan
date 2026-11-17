import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/sources/source_service.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';

/// P04 添加源（05 §3.3）：表单 + 类型选择 + 测试连接（真发请求并显示耗时）
class SourceAddPage extends ConsumerStatefulWidget {
  const SourceAddPage({super.key, this.kind, this.initialUrl});

  /// 从别处带类型进来（例如 B 站账号页），默认采集站
  final SourceKind? kind;
  final String? initialUrl;

  @override
  ConsumerState<SourceAddPage> createState() => _SourceAddPageState();
}

class _SourceAddPageState extends ConsumerState<SourceAddPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.kind?.label ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.initialUrl ?? '');
  late SourceKind _kind = widget.kind ?? SourceKind.maccms;

  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  String get _hint {
    switch (_kind) {
      case SourceKind.maccms:
        return 'https://example.com/api.php/provide/vod/';
      case SourceKind.bilibili:
        return '不用填地址，留空就行（用内置 API）';
      case SourceKind.direct:
        return 'https://example.com/movie/index.m3u8';
      case SourceKind.webdav:
        return 'https://example.com/dav/';
      case SourceKind.emby:
        return 'https://example.com/emby/';
      case SourceKind.alist:
        return 'https://example.com/alist/';
      case SourceKind.html:
        return 'https://www.hdmoli.me（网页型站点只填首页）';
      case SourceKind.tvbox:
        return 'csp_App99 或 https://…/api.php/provide/vod/（TVBox 源）';
    }
  }

  /// 测试连接：真发一次健康检查请求，把耗时显示出来
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final SourceService service = ref.read(sourceServiceProvider);
      final String url = _kind == SourceKind.bilibili
          ? 'https://api.bilibili.com/'
          : SourceService.normalizeUrl(_url.text, kind: _kind);
      final SourceHealth h = await service.probe(kind: _kind, url: url);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = !h.isDown;
        _testMessage = h.isDown
            ? '连不上${h.message == null ? '' : '：${h.message}'}'
            : '${h.health == 'ok' ? '连接正常' : '能连上但有点慢'}（${h.latencyMs}ms）';
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = e.display;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final SourceService service = ref.read(sourceServiceProvider);
      final String url = _kind == SourceKind.bilibili
          ? 'https://api.bilibili.com/'
          : _url.text;
      await service.add(
        name: _name.text,
        kind: _kind,
        url: url,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _testMessage = e.display;
        _testOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加片源')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.page),
        children: <Widget>[
          Text('名称', style: AppText.label.copyWith(color: AppColors.textSub)),
          const SizedBox(height: AppSpace.xs),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '给它起个名字'),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('类型', style: AppText.label.copyWith(color: AppColors.textSub)),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: SourceKind.values.map((SourceKind k) {
              final bool on = k == _kind;
              return ChoiceChip(
                label: Text(k.label),
                selected: on,
                onSelected: (_) => setState(() {
                  _kind = k;
                  _testMessage = null;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            _kind.needsApiUrl ? 'API 地址' : '地址',
            style: AppText.label.copyWith(color: AppColors.textSub),
          ),
          const SizedBox(height: AppSpace.xs),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(hintText: _hint),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check),
                label: const Text('测试连接'),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: _testMessage == null
                    ? const SizedBox.shrink()
                    : Text(
                        _testMessage!,
                        style: AppText.sub.copyWith(
                          color: _testOk ? AppColors.success : AppColors.danger,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            '片源只存在本机数据库里，不会上传；搜索引擎只查你自己加的这些源。',
            style: AppText.sub.copyWith(color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
