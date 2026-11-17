import 'package:flutter_test/flutter_test.dart';
import 'package:yiqikan/features/dynamic/dynamic_block.dart';

/// F13 活动页：block / action 的解析（纯数据层，不依赖 Flutter）。
///
/// 文档口径见 20_craft-anything增量情报.md §1.3/§1.4 与 05_UI规范.md §5A：
/// 9 种 block（banner/card/text/image/buttons/bullets/notice/divider/spacer）、
/// 7 种 action（url/copy/page/room/reviews/close/dismiss）。
void main() {
  group('parseBlock 九种 + 未知', () {
    test('banner', () {
      final DynBlock b = parseBlock(<String, Object?>{
        'type': 'banner',
        'image': 'https://example.com/a.png',
        'title': '限时活动',
        'badge': '限时',
        'action': <String, Object?>{'type': 'url', 'url': 'https://a.example'},
      });
      expect(b, isA<BannerBlock>());
      final BannerBlock x = b as BannerBlock;
      expect(x.image, 'https://example.com/a.png');
      expect(x.title, '限时活动');
      expect(x.badge, '限时');
      expect(x.action, isA<OpenUrlAction>());
    });

    test('card / grid / list 都归到卡片栅格与竖排', () {
      final DynBlock card = parseBlock(<String, Object?>{
        'type': 'card',
        'columns': 2,
        'items': <Object?>[
          <String, Object?>{'title': 'A'},
          <String, Object?>{'title': 'B'},
        ],
      });
      expect(card, isA<GridBlock>());
      expect((card as GridBlock).columns, 2);
      expect(card.items.length, 2);

      final DynBlock grid = parseBlock(<String, Object?>{
        'type': 'grid',
        'columns': 2,
        'items': <Object?>[
          <String, Object?>{'title': 'A'},
        ],
      });
      expect(grid, isA<GridBlock>());

      final DynBlock list = parseBlock(<String, Object?>{
        'type': 'list',
        'items': <Object?>[
          <String, Object?>{'title': 'A'},
          <String, Object?>{'title': 'B'},
          <String, Object?>{'title': 'C'},
        ],
      });
      expect(list, isA<ListBlock>());
      expect((list as ListBlock).items.length, 3);
    });

    test('text', () {
      final DynBlock b = parseBlock(<String, Object?>{
        'type': 'text',
        'text': '正文',
        'align': 'center',
        'size': 18,
      });
      expect(b, isA<TextBlock>());
      expect((b as TextBlock).text, '正文');
      expect(b.align, 'center');
      expect(b.size, 18);
    });

    test('image / buttons / bullets', () {
      expect(
        parseBlock(<String, Object?>{'type': 'image', 'image': 'u'}),
        isA<ImageBlock>(),
      );
      final DynBlock btn = parseBlock(<String, Object?>{
        'type': 'buttons',
        'label': '打开',
        'style': 'filled',
        'action': <String, Object?>{'type': 'url', 'url': 'https://b.example'},
      });
      expect(btn, isA<ButtonsBlock>());
      expect((btn as ButtonsBlock).label, '打开');

      final DynBlock bl = parseBlock(<String, Object?>{
        'type': 'bullets',
        'items': <Object?>['一', '二', '三'],
      });
      expect(bl, isA<BulletsBlock>());
      expect((bl as BulletsBlock).items.length, 3);
    });

    test('notice / divider / spacer', () {
      final DynBlock n = parseBlock(<String, Object?>{
        'type': 'notice',
        'text': '注意',
        'tone': 'warning',
      });
      expect(n, isA<NoticeBlock>());
      expect((n as NoticeBlock).tone, 'warning');

      expect(parseBlock(<String, Object?>{'type': 'divider'}), isA<DividerBlock>());
      final DynBlock sp = parseBlock(<String, Object?>{'type': 'spacer', 'size': 99});
      expect(sp, isA<SpacerBlock>());
      // 上限 48（05 §5A）
      expect((sp as SpacerBlock).size, lessThanOrEqualTo(48));
    });

    test('未知 type → UnknownBlock，带原始 type 不崩', () {
      final DynBlock b = parseBlock(<String, Object?>{'type': 'mystery_from_future'});
      expect(b, isA<UnknownBlock>());
      expect((b as UnknownBlock).rawType, 'mystery_from_future');
    });

    test('没有 type 也当未知，不抛', () {
      expect(parseBlock(<String, Object?>{}), isA<UnknownBlock>());
    });
  });

  group('parseAction 七种 + 未知', () {
    test('url 带 open_mode', () {
      final DynAction? a = parseAction(<String, Object?>{
        'type': 'url',
        'url': 'https://c.example',
        'open_mode': 'externalApplication',
      });
      expect(a, isA<OpenUrlAction>());
      expect((a as OpenUrlAction).url, 'https://c.example');
      expect(a.openMode, 'externalApplication');
    });

    test('copy', () {
      final DynAction? a = parseAction(<String, Object?>{
        'type': 'copy',
        'copy': '884010',
      });
      expect(a, isA<CopyAction>());
      expect((a as CopyAction).value, '884010');
    });

    test('page / room / reviews / close / dismiss', () {
      expect(
        parseAction(<String, Object?>{'type': 'page', 'page': '/settings'}),
        isA<PageAction>(),
      );
      final DynAction? room = parseAction(<String, Object?>{
        'type': 'room',
        'room_code': '884010',
      });
      expect(room, isA<RoomAction>());
      expect((room as RoomAction).roomCode, '884010');
      expect(parseAction(<String, Object?>{'type': 'reviews'}), isA<ReviewsAction>());
      expect(parseAction(<String, Object?>{'type': 'close'}), isA<CloseAction>());
      expect(parseAction(<String, Object?>{'type': 'dismiss'}), isA<DismissBlockAction>());
    });

    test('未知 action → UnknownAction；null → null', () {
      final DynAction? a = parseAction(<String, Object?>{'type': 'nope'});
      expect(a, isA<UnknownAction>());
      expect(parseAction(null), isNull);
    });
  });

  test('parseBlocks 整体解析并跳过非 Map 项', () {
    final List<DynBlock> bs = parseBlocks(<Object?>[
      <String, Object?>{'type': 'text', 'text': 'a'},
      'oops',
      <String, Object?>{'type': 'divider'},
    ]);
    expect(bs.length, 2);
    expect(bs.first, isA<TextBlock>());
    expect(bs.last, isA<DividerBlock>());
  });
}
