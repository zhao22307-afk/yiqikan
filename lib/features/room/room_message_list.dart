import 'package:flutter/material.dart';

import '../../domain/entities/room_message.dart';
import '../../platform/room/room_client.dart';
import '../../theme/app_colors.dart';

/// 房间消息列表（M8 第一项：只接 chats，弹幕/表情留到下一步）。
///
/// 数据来自 RoomClient 的环形缓冲（最多 200 条，按 seq 顺序进环），
/// 这里不做排序也不做 filter —— 排序要每次重建都算一遍，且环里本来就是顺序的。
class RoomMessageList extends StatelessWidget {
  const RoomMessageList({
    super.key,
    required this.client,
    required this.memberId,
  });

  final RoomClient client;

  /// 自己的成员 id：用来判定「靠右 / 浅蓝底」
  final String memberId;

  @override
  Widget build(BuildContext context) {
    // 浅色底（以前消息区是纯黑，看着像没加载）
    return ColoredBox(
      color: AppColors.bg,
      child: ValueListenableBuilder<List<ChatMessage>>(
        valueListenable: client.chats,
        builder: (BuildContext ctx, List<ChatMessage> list, Widget? _) {
          return _ChatListView(list: list, memberId: memberId);
        },
      ),
    );
  }
}

class _ChatListView extends StatefulWidget {
  const _ChatListView({required this.list, required this.memberId});

  final List<ChatMessage> list;
  final String memberId;

  @override
  State<_ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<_ChatListView> {
  final ScrollController _scroll = ScrollController();

  /// 用户当前是否就在底部（距底部 < 40px）。往上翻过就不再抢他的位置。
  bool _atBottom = true;

  /// 不在底部时攒下的新消息条数，显示成聊天栏上方的胶囊。
  int _unseen = 0;

  int _lastLen = 0;

  @override
  void initState() {
    super.initState();
    _lastLen = widget.list.length;
    _scroll.addListener(_onScroll);
    // 首次进来直接落到底部（重连补历史时不至于停在最上面）
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ScrollPosition p = _scroll.position;
    final bool bottom = (p.maxScrollExtent - p.pixels) < 40;
    if (bottom != _atBottom) {
      // 自己滑回底部：胶囊一起收掉
      setState(() {
        _atBottom = bottom;
        if (bottom) _unseen = 0;
      });
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _animateToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(_ChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int len = widget.list.length;
    if (len == _lastLen) return;
    final int delta = len - _lastLen;
    _lastLen = len;

    // 撤回（chat-recall）会让列表变短：offset 超出新范围必须夹回来，
    // 否则 ListView 会拿越界的 offset 去算可见区，抛 RangeError。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ScrollPosition p = _scroll.position;
      if (p.pixels > p.maxScrollExtent) {
        _scroll.jumpTo(p.maxScrollExtent);
      }
      if (delta > 0) {
        if (_atBottom) {
          _jumpToBottom();
          if (_unseen != 0) setState(() => _unseen = 0);
        } else {
          setState(() => _unseen += delta);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.list.isEmpty) return const _EmptyHint();
    return Stack(
      children: <Widget>[
        ListView.builder(
          controller: _scroll,
          reverse: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: widget.list.length,
          itemBuilder: (BuildContext c, int i) {
            final ChatMessage m = widget.list[i];
            return _Bubble(m: m, mine: m.from == widget.memberId);
          },
        ),
        if (_unseen > 0)
          Positioned(
            bottom: AppSpace.xs,
            left: 0,
            right: 0,
            child: Center(
              child: _NewMessagesPill(
                count: _unseen,
                onTap: () {
                  setState(() {
                    _unseen = 0;
                    _atBottom = true;
                  });
                  _animateToBottom();
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            '房间消息会出现在这里',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
        ),
      ),
    );
  }
}

/// 聊天栏上方的「N 条新消息」胶囊：点一下滚到底。
class _NewMessagesPill extends StatelessWidget {
  const _NewMessagesPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadow.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$count 条新消息',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textOn,
              ),
            ),
            const SizedBox(width: AppSpace.xxs),
            Icon(Icons.arrow_downward,
                size: 14, color: AppColors.textOn),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.mine});

  final ChatMessage m;
  final bool mine;

  /// 同一人恒定：memberId 哈希取色，不随会话变。
  /// 批 E11 起是 getter（颜色跟着主题走），所以不能再是 `static const`。
  static List<Color> get _avatarColors => <Color>[
        AppColors.primary,
        AppColors.primaryEnd,
        AppColors.accent,
        AppColors.info,
        AppColors.success,
        AppColors.warn,
        AppColors.danger,
      ];

  Color get _avatarColor {
    int h = 0;
    for (final int u in m.from.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _avatarColors[h % _avatarColors.length];
  }

  String get _initial {
    final String n = m.name.trim().isEmpty ? '客' : m.name.trim();
    return n.substring(0, 1);
  }

  String get _time {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(
      m.at == 0 ? DateTime.now().millisecondsSinceEpoch : m.at,
    ).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final bool supported = m.kind == 'text';
    final Widget body = supported
        ? Text(
            m.text,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.text,
            ),
          )
        : Text(
            '[暂不支持的消息类型]',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          );

    final Widget bubble = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: mine ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.md),
          topRight: const Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(mine ? AppRadius.md : AppRadius.sm),
          bottomRight: Radius.circular(mine ? AppRadius.sm : AppRadius.md),
        ),
        // 05 §1：禁止纯黑阴影，必须带蓝味
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x0A102040), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          if (supported && m.text.trim().isEmpty)
            Text('（空消息）',
                style: TextStyle(fontSize: 13, color: AppColors.textDim))
          else
            body,
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!mine) ...<Widget>[
            _Avatar(color: _avatarColor, initial: _initial),
            const SizedBox(width: AppSpace.xs),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (!mine)
                      Text(
                        m.name.trim().isEmpty ? '客人' : m.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSub,
                        ),
                      ),
                    if (!mine) const SizedBox(width: AppSpace.xs),
                    Text(
                      _time,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                bubble,
              ],
            ),
          ),
          if (mine) ...<Widget>[
            const SizedBox(width: AppSpace.xs),
            _Avatar(color: _avatarColor, initial: _initial),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.color, required this.initial});

  final Color color;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.soft(color, 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}