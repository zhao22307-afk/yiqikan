part of '../app_database.dart';

/// 弹幕缓存 DAO（03 §4.6）
///
/// 缓存带 TTL：过期的弹幕宁可不显示，也不显示别人昨天的旧数据。
@DriftAccessor(tables: <Type>[DanmakuCacheTable])
class DanmakuDao extends DatabaseAccessor<AppDatabase>
    with _$DanmakuDaoMixin {
  DanmakuDao(super.db);

  /// 默认缓存 6 小时（同一个媒体一整个晚上都够用）
  static const Duration _defaultTtl = Duration(hours: 6);

  /// 未过期才返回
  Future<DanmakuPayload?> get(String mediaId, int episodeIndex) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final DanmakuRow? row = await (select(danmakuCacheTable)
          ..where(($DanmakuCacheTableTable t) =>
              t.mediaId.equals(mediaId) &
              t.episodeIndex.equals(episodeIndex) &
              t.expiresAt.isBiggerThanValue(now)))
        .getSingleOrNull();
    if (row == null) return null;

    return DanmakuPayload(
      mediaId: row.mediaId,
      episodeIndex: row.episodeIndex,
      items: DanmakuPayload.decodeItems(row.payload),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(row.fetchedAt),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(row.expiresAt),
    );
  }

  Future<void> put(
    String mediaId,
    int episodeIndex,
    List<DanmakuItem> items, {
    Duration ttl = _defaultTtl,
  }) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final DanmakuPayload payload = DanmakuPayload(
      mediaId: mediaId,
      episodeIndex: episodeIndex,
      items: items,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(now),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        now + ttl.inMilliseconds,
      ),
    );

    return into(danmakuCacheTable).insertOnConflictUpdate(
      DanmakuCacheTableCompanion.insert(
        mediaId: mediaId,
        episodeIndex: Value<int>(episodeIndex),
        payload: payload.encodeItems(),
        count: items.length,
        fetchedAt: now,
        expiresAt: now + ttl.inMilliseconds,
      ),
    );
  }

  Future<void> purgeExpired() {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return (delete(danmakuCacheTable)
          ..where(($DanmakuCacheTableTable t) =>
              t.expiresAt.isSmallerOrEqualValue(now)))
        .go();
  }

  Future<void> clearAll() => delete(danmakuCacheTable).go();

  // ---------------------------------------------------------------------
  // F11 弹幕库（E7 B 组）：把「收藏的单条弹幕」也放这张表里，不新增表/列。
  //
  // 复用方式：`mediaId = 'fav:<hash>'`、`episodeIndex = 0`、
  // `payload = [ {text, mediaUrl, room, pos, at} ]`、`count = 1`、
  // `expiresAt = 2100-01-01`（purgeExpired 按 expiresAt<=now 删，永远命中不到）。
  // 主键是 (mediaId, episodeIndex)，所以 text+mediaUrl 相同天然去重。
  // ---------------------------------------------------------------------

  static const String favPrefix = 'fav:';

  /// 2100-01-01 00:00:00 UTC —— 收藏不过期
  static const int _favExpiresAt = 4102444800000;

  /// 稳定指纹（FNV-1a 64）。不用 String.hashCode：它跨进程/跨版本不保证一致，
  /// 去重要求「重启后还是同一个 id」。也不引 crypto，省一个 import。
  static String favId(String text, String mediaUrl) {
    const int prime = 0x100000001b3;
    int h = 0xcbf29ce484222325;
    final String src = '$text\u0001$mediaUrl';
    for (final int c in src.codeUnits) {
      h ^= c;
      h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return '$favPrefix${h.toUnsigned(64).toRadixString(16).padLeft(16, '0')}';
  }

  Future<bool> favExists(String text, String mediaUrl) async {
    final String id = favId(text, mediaUrl);
    final DanmakuRow? row = await (select(danmakuCacheTable)
          ..where(($DanmakuCacheTableTable t) => t.mediaId.equals(id)))
        .getSingleOrNull();
    return row != null;
  }

  /// 收藏一条；返回 true 表示新加的，false 表示本来就有（去重）
  Future<bool> favPut({
    required String text,
    required String mediaUrl,
    required double pos,
    String room = '',
    int? at,
  }) async {
    final String id = favId(text, mediaUrl);
    final int now = at ?? DateTime.now().millisecondsSinceEpoch;
    final bool existed = await favExists(text, mediaUrl);
    final String payload = jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'text': text,
        'mediaUrl': mediaUrl,
        'room': room,
        'pos': pos,
        'at': now,
      },
    ]);
    await into(danmakuCacheTable).insertOnConflictUpdate(
      DanmakuCacheTableCompanion.insert(
        mediaId: id,
        payload: payload,
        count: 1,
        fetchedAt: now,
        expiresAt: _favExpiresAt,
      ),
    );
    return !existed;
  }

  /// `room` 非空时只返回这个房间收的
  Future<List<DanmakuFav>> favList({String? room}) async {
    final List<DanmakuRow> rows = await (select(danmakuCacheTable)
          ..where(($DanmakuCacheTableTable t) =>
              t.mediaId.like('$favPrefix%'))
          ..orderBy(<OrderClauseGenerator<$DanmakuCacheTableTable>>[
            ($DanmakuCacheTableTable t) => OrderingTerm.desc(t.fetchedAt),
          ]))
        .get();
    final List<DanmakuFav> out = <DanmakuFav>[];
    for (final DanmakuRow r in rows) {
      try {
        final Object? j = jsonDecode(r.payload);
        if (j is! List || j.isEmpty) continue;
        final Map<String, dynamic> m =
            (j.first as Map<Object?, Object?>).cast<String, dynamic>();
        final DanmakuFav f = DanmakuFav(
          id: r.mediaId,
          text: (m['text'] as String?) ?? '',
          mediaUrl: (m['mediaUrl'] as String?) ?? '',
          room: (m['room'] as String?) ?? '',
          pos: (m['pos'] as num?)?.toDouble() ?? 0,
          at: (m['at'] as num?)?.toInt() ?? r.fetchedAt,
        );
        if (room != null && room.isNotEmpty && f.room != room) continue;
        out.add(f);
      } catch (_) {
        // 坏行跳过，不因为一条烂 JSON 让整页空掉
      }
    }
    return out;
  }

  Future<void> favRemove(String id) => (delete(danmakuCacheTable)
        ..where(($DanmakuCacheTableTable t) => t.mediaId.equals(id)))
      .go();
}

/// 一条被收藏的弹幕（F11）
class DanmakuFav {
  const DanmakuFav({
    required this.id,
    required this.text,
    required this.mediaUrl,
    required this.room,
    required this.pos,
    required this.at,
  });

  final String id;
  final String text;
  final String mediaUrl;

  /// 收藏时所在房间号（空 = 不在房间里看的）
  final String room;

  /// 相对视频的秒数
  final double pos;

  /// 收藏时刻（毫秒）
  final int at;

  DateTime get atTime => DateTime.fromMillisecondsSinceEpoch(at);

  /// 来源一行字：房间优先，否则用片名
  String get source {
    if (room.isNotEmpty) return '房间 $room';
    final Uri? u = Uri.tryParse(mediaUrl);
    final String last = (u != null && u.pathSegments.isNotEmpty)
        ? u.pathSegments.last
        : mediaUrl;
    return last.isEmpty ? '本机' : last;
  }
}
