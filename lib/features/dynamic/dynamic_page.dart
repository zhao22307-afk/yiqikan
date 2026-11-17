import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../routing/routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../player/player_controller.dart';
import '../room/room_entry.dart';
import 'dynamic_block.dart';

/// F13 活动页渲染器（10 号 :151 / 20 号 §1）。
///
/// 数据来自本机服务 `GET /local/dynamic?id=<id>`（读 assets/dynamic/<id>.json，
/// 原包是 `/api/dynamic_ui/{id}`；本机版只做离线运营位，不走公网）。
/// 渲染原则：一个 block 一张卡、配错一个 block 不毁整页，未知类型跳过 + warn。
class DynamicPage extends StatefulWidget {
  const DynamicPage({super.key, required this.id});

  final String id;

  @override
  State<DynamicPage> createState() => _DynamicPageState();
}

class _DynamicPageState extends State<DynamicPage> {
  late Future<List<DynBlock>> _future;
  String? _error;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      // 404 也要读 body，自己判
      validateStatus: _any,
    ),
  );

  static bool _any(int? _) => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DynBlock>> _load() async {
    final String url = '$kLocalServerBase/local/dynamic?id=${widget.id}';
    try {
      final Response<dynamic> r = await _dio.get<dynamic>(url);
      final int code = r.statusCode ?? 0;
      final Object? data = r.data;
      final Map<String, Object?>? j = data is String
          ? (jsonDecode(data) as Map<String, dynamic>).cast<String, Object?>()
          : (data is Map ? data.cast<String, Object?>() : null);
      if (code == 404 || j == null || j['success'] != true) {
        _error = code == 404 ? '这个活动不存在或已下线' : '内容加载失败，请稍后重试';
        debugPrint('[YQK-DYN] load id=${widget.id} http=$code fail');
        return const <DynBlock>[];
      }
      final List<DynBlock> blocks = parseBlocks(j['blocks']);
      debugPrint('[YQK-DYN] load id=${widget.id} blocks=${blocks.length}');
      for (final DynBlock b in blocks) {
        if (b is UnknownBlock) {
          debugPrint('[YQK-DYN] skip type=${b.rawType}');
        }
      }
      return blocks;
    } catch (e) {
      _error = '内容加载失败，请稍后重试';
      debugPrint('[YQK-DYN] load id=${widget.id} error=$e');
      return const <DynBlock>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('活动'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: FutureBuilder<List<DynBlock>>(
        future: _future,
        builder: (BuildContext ctx, AsyncSnapshot<List<DynBlock>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<DynBlock> blocks = snap.data ?? const <DynBlock>[];
          if (blocks.isEmpty) {
            return _empty(_error ?? '内容还没配置好', retry: _error != null);
          }
          final List<DynBlock> visible =
              blocks.where((DynBlock b) => b is! UnknownBlock).toList();
          if (visible.isEmpty) return _empty('内容还没配置好');
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            itemCount: visible.length,
            itemBuilder: (BuildContext c, int i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _block(visible[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(String text, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.inbox_outlined, size: 40, color: AppColors.textDim),
          const SizedBox(height: 10),
          Text(text, style: AppText.sub.copyWith(color: AppColors.textDim)),
          if (retry)
            TextButton(
              onPressed: () => setState(() {
                _error = null;
                _future = _load();
              }),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  Widget _block(DynBlock b) {
    if (b is BannerBlock) return _banner(b);
    if (b is GridBlock) return _grid(b);
    if (b is ListBlock) return _list(b);
    if (b is TextBlock) return _text(b);
    if (b is ImageBlock) return _image(b);
    if (b is ButtonsBlock) return _buttons(b);
    if (b is BulletsBlock) return _bullets(b);
    if (b is NoticeBlock) return _notice(b);
    if (b is DividerBlock) {
      return const Divider(height: 8, thickness: 1, color: Color(0xFFE6ECF5));
    }
    if (b is SpacerBlock) return SizedBox(height: b.size.clamp(0, 48));
    return const SizedBox.shrink();
  }

  Widget _banner(BannerBlock b) {
    return GestureDetector(
      onTap: b.action == null ? null : () => unawaited(_run(b.action!)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _img(b.image),
              // 底部渐变必须从黑到透明往上，否则白底上的白字看不见（05 §5A.2）
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[Colors.black54, Colors.transparent],
                  ),
                ),
              ),
              if (b.badge != null)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(b.badge!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11)),
                  ),
                ),
              if ((b.title ?? b.subtitle ?? b.caption) != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (b.title != null)
                        Text(b.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                      if (b.subtitle != null)
                        Text(b.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      if (b.caption != null)
                        Text(b.caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(GridBlock b) {
    return GridView.count(
      crossAxisCount: b.columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.78,
      children: <Widget>[
        for (final DynTile t in b.items) _tile(t),
      ],
    );
  }

  Widget _list(ListBlock b) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < b.items.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              leading: b.items[i].image == null
                  ? Icon(Icons.movie_outlined, color: AppColors.textDim)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 40,
                        height: 56,
                        child: _img(b.items[i].image!),
                      ),
                    ),
              title: Text(b.items[i].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: b.items[i].subtitle == null
                  ? null
                  : Text(b.items[i].subtitle!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: b.items[i].action == null
                  ? null
                  : () => unawaited(_run(b.items[i].action!)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(DynTile t) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: t.action == null ? null : () => unawaited(_run(t.action!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.expand(
                child: t.image == null ? _ph() : _img(t.image!),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          if (t.subtitle != null)
            Text(t.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.textDim)),
        ],
      ),
    );
  }

  Widget _text(TextBlock b) {
    final TextAlign a = b.align == 'center'
        ? TextAlign.center
        : (b.align == 'right' ? TextAlign.right : TextAlign.left);
    return Text(
      b.text,
      textAlign: a,
      style: TextStyle(
        fontSize: b.size,
        height: 1.6,
        color: AppColors.text,
      ),
    );
  }

  Widget _image(ImageBlock b) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: _img(b.image),
      ),
    );
  }

  Widget _buttons(ButtonsBlock b) {
    final bool filled = b.style == 'filled';
    final bool tonal = b.style == 'tonal';
    final bool outlined = b.style == 'outlined';
    return SizedBox(
      height: 44,
      child: filled
          ? FilledButton(
              onPressed: b.action == null ? null : () => unawaited(_run(b.action!)),
              child: Text(b.label),
            )
          : tonal
              ? FilledButton.tonal(
                  onPressed:
                      b.action == null ? null : () => unawaited(_run(b.action!)),
                  child: Text(b.label),
                )
              : outlined
                  ? OutlinedButton(
                      onPressed: b.action == null
                          ? null
                          : () => unawaited(_run(b.action!)),
                      child: Text(b.label),
                    )
                  : TextButton(
                      onPressed: b.action == null
                          ? null
                          : () => unawaited(_run(b.action!)),
                      child: Text(b.label),
                    ),
    );
  }

  Widget _bullets(BulletsBlock b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String s in b.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 7, right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(child: Text(s, style: const TextStyle(height: 1.5))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _notice(NoticeBlock b) {
    final (Color bg, Color bar, Color fg) = switch (b.tone) {
      'warning' => (const Color(0xFFFFF7E8), const Color(0xFFD97706),
          const Color(0xFFB45309)),
      'success' => (const Color(0xFFECFDF3), const Color(0xFF059669),
          const Color(0xFF047857)),
      _ => (const Color(0xFFEFF4FF), const Color(0xFF2563EB),
          const Color(0xFF1E4FD8)),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: bar, width: 2)),
      ),
      child: Text(b.text, style: TextStyle(color: fg, fontSize: 13)),
    );
  }

  Widget _img(String url) {
    if (!url.startsWith('http')) return _ph();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => _ph(),
    );
  }

  Widget _ph() => Container(
        color: AppColors.surface3,
        child: Icon(Icons.image_outlined, color: AppColors.textDim),
      );

  Future<void> _run(DynAction a) async {
    debugPrint('[YQK-DYN] action type=${a.type}'
        '${a is OpenUrlAction ? ' url=${a.url}' : ''}'
        '${a is OpenVideoAction ? ' url=${a.url}' : ''}'
        '${a is RoomAction ? ' room=${a.roomCode}' : ''}'
        '${a is PageAction ? ' page=${a.page}' : ''}');
    if (a is OpenUrlAction) {
      final Uri uri = Uri.tryParse(a.url) ?? Uri();
      bool ok = false;
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('[YQK-DYN] launch fail $e');
      }
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打不开这个链接')),
        );
      }
      return;
    }
    if (a is OpenVideoAction) {
      if (!mounted) return;
      unawaited(context.push<Object?>(
        Routes.player,
        extra: PlayerMedia(
          id: 'dyn_${a.url.hashCode}',
          title: a.title ?? '活动视频',
          url: a.url,
          sourceKind: 'dynamic',
        ),
      ));
      return;
    }
    if (a is CopyAction) {
      await Clipboard.setData(ClipboardData(text: a.value));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已复制')));
      }
      return;
    }
    if (a is PageAction) {
      if (!mounted) return;
      final String p = a.page.startsWith('/') ? a.page : '/${a.page}';
      try {
        context.push<Object?>(p);
      } catch (e) {
        debugPrint('[YQK-DYN] page miss $p $e'); // 路由不存在就静默，别崩
      }
      return;
    }
    if (a is RoomAction) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在进入房间 ${a.roomCode}…')),
      );
      await joinRoomAndEnter(context, a.roomCode, from: JoinFrom.manual);
      return;
    }
    if (a is ReviewsAction) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('影评功能暂未开放')),
        );
      }
      return;
    }
    if (a is CloseAction || a is DismissBlockAction) {
      debugPrint('[YQK-DYN] ${a.type} page');
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    debugPrint('[YQK-DYN] skip action type=${a.type}');
  }
}