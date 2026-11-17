/// 调试构建专用的「先解析再播」入口（`/play?resolve=1&url=...`）。
///
/// 正常用户路径是「片源里搜索 → 点结果」，解析由 [SourcesPage] 调 [Resolver] 完成；
/// 这个页面只是把同一条链路拉出来，方便在真机上验证番剧/直播/缓存命中，
/// 只在 kDebugMode 下挂路由。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/failure_text.dart';
import '../../domain/resolver.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import 'player_controller.dart';
import 'player_page.dart';

class ResolveGatePage extends ConsumerStatefulWidget {
  const ResolveGatePage({
    super.key,
    required this.url,
    this.expireFirst = false,
    this.repeat = 1,
    this.failKind,
  });

  final String url;

  /// true = 解析前先手动把缓存有效期拨到过去（B19-d）
  final bool expireFirst;

  /// 连解几次（B19-c 验收用：同一进程里第二次必须 cache hit）
  final int repeat;

  /// 验收用：直接注入一类失败，验证五类文案的渲染（映射与线上同一条）
  final String? failKind;

  @override
  ConsumerState<ResolveGatePage> createState() => _ResolveGatePageState();
}

class _ResolveGatePageState extends ConsumerState<ResolveGatePage> {
  String? _error;
  Map<String, String> _stages = <String, String>{};
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final Resolver resolver = ref.read(resolverProvider);
    if (widget.expireFirst) {
      final int n = resolver.debugExpireAll();
      debugPrint('[YQK-CACHE] expireFirst=$n 条');
    }
    try {
      if (widget.failKind == 'login') throw const AuthRequiredException();
      if (widget.failKind == 'offline') throw const NetworkException();
      if (widget.failKind == 'source') throw const InvalidSourceException('域名解析不了');
      ResolvedUrl r = const ResolvedUrl(url: '', resolver: '');
      for (int i = 1; i <= widget.repeat; i++) {
        final ResolvedUrl got = await resolver.resolve(widget.url);
        debugPrint('[YQK-CACHE] repeat#$i resolver=${got.resolver} '
            'url=${got.url.length > 60 ? got.url.substring(0, 60) : got.url}');
        if (i == 1) r = got;
      }
      debugPrint('[YQK-CACHE] 解析完成 resolver=${r.resolver} '
          'cacheSize=${resolver.cacheSize} upstream=${resolver.debugUpstream}');
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => PlayerPage(
            media: PlayerMedia(
              id: widget.url,
              title: r.resolver,
              url: r.url,
              sourceKind: r.resolver,
              headers: r.headers,
            ),
          ),
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = FailureText.detailOf(e);
        if (e is ResolveFailedException) _stages = e.stageErrors;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = FailureText.detailOf(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('解析')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.page),
        child: ListView(
          children: <Widget>[
            Text(_error ?? FailureText.unknown.display, style: AppText.body),
            if (_stages.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.md),
              Text('每一档为什么失败', style: AppText.section),
              const SizedBox(height: AppSpace.sm),
              for (final MapEntry<String, String> e in _stages.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Text('${e.key}：${e.value}', style: AppText.sub),
                ),
            ],
          ],
        ),
      ),
    );
  }
}