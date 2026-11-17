/// F13 活动页（dynamic_ui）的 block / action 数据模型。
///
/// 规格来自 `20_craft-anything增量情报.md §1.3/§1.4`：
///   9 种 block：banner / card / text / image / buttons / bullets / notice / divider / spacer
///   7 种 action：url / copy / page / room / reviews / close / dismiss
/// 本文件**故意不 import flutter/material**：纯数据 + fromJson，能被单测直接打到。
/// 没见过的 type 一律落到 UnknownBlock / UnknownAction，渲染层跳过并打日志，不崩。
library;

/// 活动页的一个 block。
sealed class DynBlock {
  const DynBlock();

  /// 原始 type 字符串（日志/兜底用）
  String get type;
}

/// 顶部大图横幅（`banner`）：16:9 图 + 底部渐变 + 可选标题。
final class BannerBlock extends DynBlock {
  const BannerBlock({
    required this.image,
    this.title,
    this.badge,
    this.subtitle,
    this.caption,
    this.dismissible = false,
    this.action,
  });

  final String image;
  final String? title;
  final String? badge;
  final String? subtitle;
  final String? caption;
  final bool dismissible;
  final DynAction? action;

  @override
  String get type => 'banner';
}

/// 网格（`grid`）：C 组新增的运营位，2 列 4 项这种。
final class GridBlock extends DynBlock {
  const GridBlock({required this.columns, required this.items});

  final int columns;
  final List<DynTile> items;

  @override
  String get type => 'grid';
}

/// 竖排条目（`list`）：一行一条，左图右文。
final class ListBlock extends DynBlock {
  const ListBlock({required this.items});

  final List<DynTile> items;

  @override
  String get type => 'list';
}

/// 段落（`text`）：align = left/center/right。
final class TextBlock extends DynBlock {
  const TextBlock({
    required this.text,
    this.align = 'left',
    this.size = 15,
  });

  final String text;
  final String align;
  final double size;

  @override
  String get type => 'text';
}

/// 单图（`image`）：满宽、圆角，高度上限 360。
final class ImageBlock extends DynBlock {
  const ImageBlock({required this.image, this.foreground});

  final String image;
  final String? foreground;

  @override
  String get type => 'image';
}

/// 按钮组（`buttons`）：label + action + style。
final class ButtonsBlock extends DynBlock {
  const ButtonsBlock({
    required this.label,
    this.style = 'filled',
    this.action,
  });

  final String label;

  /// filled / tonal / outlined / text
  final String style;
  final DynAction? action;

  @override
  String get type => 'buttons';
}

/// 无序列表（`bullets`）。
final class BulletsBlock extends DynBlock {
  const BulletsBlock({required this.items});

  final List<String> items;

  @override
  String get type => 'bullets';
}

/// 提示条（`notice`）：tone = info / warning / success。
final class NoticeBlock extends DynBlock {
  const NoticeBlock({required this.text, this.tone = 'info'});

  final String text;
  final String tone;

  @override
  String get type => 'notice';
}

/// 分隔线（`divider`）。
final class DividerBlock extends DynBlock {
  const DividerBlock();

  @override
  String get type => 'divider';
}

/// 留白（`spacer`）：size 上限 48。
final class SpacerBlock extends DynBlock {
  const SpacerBlock({this.size = 12});

  final double size;

  @override
  String get type => 'spacer';
}

/// 没见过的 block：渲染层跳过 + warn，不崩。
final class UnknownBlock extends DynBlock {
  const UnknownBlock(this.rawType);

  final String rawType;

  @override
  String get type => rawType;
}

/// grid / list 里的一格。
final class DynTile {
  const DynTile({
    required this.title,
    this.image,
    this.subtitle,
    this.action,
  });

  final String? image;
  final String title;
  final String? subtitle;
  final DynAction? action;

  static DynTile parse(Map<String, Object?> j) {
    return DynTile(
      image: _str(j['image']),
      title: _str(j['title']) ?? '',
      subtitle: _str(j['subtitle']),
      action: parseAction(j['action']),
    );
  }
}

/// 一个点击行为。
sealed class DynAction {
  const DynAction();

  String get type;
}

/// 打开链接（`url`）：openMode = platformDefault / externalApplication / inAppWebView。
final class OpenUrlAction extends DynAction {
  const OpenUrlAction({required this.url, this.openMode = 'platformDefault'});

  final String url;
  final String openMode;

  @override
  String get type => 'url';
}

/// 直接播一个视频（C 组的便捷写法，等价于 `page` + 播放路由）。
final class OpenVideoAction extends DynAction {
  const OpenVideoAction({required this.url, this.title});

  final String url;
  final String? title;

  @override
  String get type => 'video';
}

/// 复制到剪贴板（`copy`）。
final class CopyAction extends DynAction {
  const CopyAction({required this.value});

  final String value;

  @override
  String get type => 'copy';
}

/// 跳 App 内路由（`page`）。
final class PageAction extends DynAction {
  const PageAction({required this.page});

  final String page;

  @override
  String get type => 'page';
}

/// 直接进房间（`room`）：活动页一键拉人进房。
final class RoomAction extends DynAction {
  const RoomAction({required this.roomCode});

  final String roomCode;

  @override
  String get type => 'room';
}

/// 影评（`reviews`）：原包未开放，只保留枚举。
final class ReviewsAction extends DynAction {
  const ReviewsAction();

  @override
  String get type => 'reviews';
}

/// 关闭活动页（`close`）。
final class CloseAction extends DynAction {
  const CloseAction();

  @override
  String get type => 'close';
}

/// 关闭并记住不再显示（`dismiss`）。
final class DismissBlockAction extends DynAction {
  const DismissBlockAction();

  @override
  String get type => 'dismiss';
}

/// 没见过的 action。
final class UnknownAction extends DynAction {
  const UnknownAction(this.rawType);

  final String rawType;

  @override
  String get type => rawType;
}

/// 把一个 block 的 JSON 解析成模型；认不出的 type → [UnknownBlock]。
DynBlock parseBlock(Map<String, Object?> j) {
  final String t = (_str(j['type']) ?? '').toLowerCase();
  switch (t) {
    case 'banner':
      return BannerBlock(
        image: _str(j['image']) ?? '',
        title: _str(j['title']),
        badge: _str(j['badge']),
        subtitle: _str(j['subtitle']),
        caption: _str(j['caption']),
        dismissible: j['dismissible'] == true,
        action: parseAction(j['action']),
      );
    case 'card':
      // 文档的 card 是单张卡片；带 items 时按栅格铺（1 列即竖排卡片）
      final List<DynTile> cards = _tiles(j['items']);
      if (cards.isNotEmpty) {
        return GridBlock(
          columns: _int(j['columns'], 2).clamp(1, 6).toInt(),
          items: cards,
        );
      }
      return GridBlock(columns: 1, items: <DynTile>[DynTile.parse(j)]);
    case 'grid':
      return GridBlock(
        columns: _int(j['columns'], 2).clamp(1, 6).toInt(),
        items: _tiles(j['items']),
      );
    case 'list':
      return ListBlock(items: _tiles(j['items']));
    case 'text':
      return TextBlock(
        text: _str(j['text']) ?? _str(j['label']) ?? '',
        align: (_str(j['align']) ?? 'left').toLowerCase(),
        size: _double(j['size'], 15),
      );
    case 'image':
      return ImageBlock(
        image: _str(j['image']) ?? '',
        foreground: _str(j['foreground']),
      );
    case 'buttons':
      return ButtonsBlock(
        label: _str(j['label']) ?? '立即参与',
        style: (_str(j['style']) ?? 'filled').toLowerCase(),
        action: parseAction(j['action']),
      );
    case 'bullets':
      return BulletsBlock(items: _strings(j['bullets'] ?? j['items']));
    case 'notice':
      return NoticeBlock(
        text: _str(j['text']) ?? _str(j['message']) ?? '',
        tone: (_str(j['tone']) ?? 'info').toLowerCase(),
      );
    case 'divider':
      return const DividerBlock();
    case 'spacer':
      return SpacerBlock(size: _double(j['size'], 12).clamp(0, 48).toDouble());
    default:
      return UnknownBlock(t.isEmpty ? '(empty)' : t);
  }
}

/// 把 action 的 JSON 解析成模型；null / 认不出 → null 或 [UnknownAction]。
DynAction? parseAction(Object? raw) {
  if (raw is! Map) return null;
  final Map<String, Object?> j = raw.cast<String, Object?>();
  final String t = (_str(j['type']) ?? '').toLowerCase();
  switch (t) {
    case 'url':
    case 'open_url':
      final String u = _str(j['url']) ?? '';
      if (u.isEmpty) return const UnknownAction('url(empty)');
      return OpenUrlAction(
        url: u,
        openMode: (_str(j['open_mode']) ?? 'platformDefault'),
      );
    case 'video':
    case 'open_video':
      final String u = _str(j['url']) ?? '';
      if (u.isEmpty) return const UnknownAction('video(empty)');
      return OpenVideoAction(url: u, title: _str(j['title']));
    case 'copy':
      return CopyAction(value: _str(j['copy']) ?? _str(j['value']) ?? '');
    case 'page':
      return PageAction(page: _str(j['page']) ?? '');
    case 'room':
      final String code = _str(j['room_code']) ?? '';
      if (code.isEmpty) return const UnknownAction('room(empty)');
      return RoomAction(roomCode: code);
    case 'reviews':
      return const ReviewsAction();
    case 'close':
      return const CloseAction();
    case 'dismiss':
      return const DismissBlockAction();
    default:
      return UnknownAction(t.isEmpty ? '(empty)' : t);
  }
}

/// 整页：blocks 数组 → 模型列表（坏条目落 UnknownBlock，不抛）。
List<DynBlock> parseBlocks(Object? raw) {
  if (raw is! List) return const <DynBlock>[];
  final List<DynBlock> out = <DynBlock>[];
  for (final Object? e in raw) {
    if (e is Map) {
      out.add(parseBlock(e.cast<String, Object?>()));
    }
    // 非 Map 的条目（脏数据）直接丢，别把整个页面拖崩
  }
  return out;
}

List<DynTile> _tiles(Object? raw) {
  if (raw is! List) return const <DynTile>[];
  return <DynTile>[
    for (final Object? e in raw)
      if (e is Map) DynTile.parse(e.cast<String, Object?>()),
  ];
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[for (final Object? e in raw) if (e != null) '$e'];
}

String? _str(Object? v) {
  if (v == null) return null;
  final String s = '$v'.trim();
  return s.isEmpty ? null : s;
}

int _int(Object? v, int def) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? def;
}

double _double(Object? v, double def) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? def;
}
