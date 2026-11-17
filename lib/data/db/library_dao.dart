import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';

import 'app_database.dart';

/// 一条片子的最小描述（数据层自己的结构）。
///
/// 这里刻意不收 [PlayerMedia]：03 §2.1 规定数据层不许反向依赖 features，
/// 所以播放页那边用 [LibraryMedia.of] 把 PlayerMedia 拆成这几个字段再进来。
class LibraryMedia {
  const LibraryMedia({
    required this.title,
    required this.url,
    this.sourceKind = 'local',
    this.sourceId,
    this.poster,
    this.episodeIndex,
  });

  final String title;
  final String url;
  final String sourceKind;
  final String? sourceId;
  final String? poster;
  final int? episodeIndex;

  /// 历史表/收藏表的主键：url 的 md5 前 16 位（与 tables.dart 的注释一致）
  String get id => md5.convert(utf8.encode(url)).toString().substring(0, 16);
}

/// 收藏 / 稍后看 / 历史 的统一入口（F1，10 号 :135-151）。
///
/// 表结构不改：稍后看复用 `favorites.tag = 'later'`，历史复用 `history`。
class LibraryDao {
  LibraryDao(this.db);

  final AppDatabase db;

  /// 稍后看的标记（favorites.tag）
  static const String laterTag = 'later';

  /// 追番的标记（favorites.tag）。单个 tag 只能有一个值：
  /// 收藏 + 追番同时存在时按「追番优先」，取消追番会清空 tag 回到普通收藏。
  static const String followTag = 'follow';

  // ── 收藏 ────────────────────────────────────────────────

  /// 收藏/取消。按 url 去重（表上 idx_fav_url 唯一）。
  ///
  /// 返回 true = 现在已收藏，false = 刚取消。
  Future<bool> toggleFavorite(LibraryMedia m) async {
    final Favorite? hit = await _favoriteByUrl(m.url);
    if (hit != null) {
      await db.favoriteDao.remove(hit.id);
      return false;
    }
    await db.favoriteDao.add(Favorite(
      id: m.id,
      title: m.title,
      url: m.url,
      sourceKind: m.sourceKind,
      sourceId: m.sourceId,
      poster: m.poster,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return true;
  }

  Future<bool> isFavorite(String url) async => (await _favoriteByUrl(url)) != null;

  Future<List<Favorite>> listFavorites({int limit = 200}) async {
    final List<Favorite> all = await db.favoriteDao.all();
    // 稍后看是 tag='later'、追番是 tag='follow'，收藏列表都不混进来
    final List<Favorite> plain = all
        .where((Favorite f) => f.tag != laterTag && f.tag != followTag)
        .toList();
    return plain.length > limit ? plain.sublist(0, limit) : plain;
  }

  Future<void> removeFavorite(String id) => db.favoriteDao.remove(id);

  Future<void> clearFavorites() async {
    for (final Favorite f in await listFavorites(limit: 1 << 30)) {
      await db.favoriteDao.remove(f.id);
    }
  }

  // ── 稍后看（favorites.tag = 'later'）────────────────────

  Future<bool> markWatchLater(LibraryMedia m) async {
    final Favorite? hit = await _favoriteByUrl(m.url);
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (hit != null) {
      if (hit.tag == laterTag) {
        // 再点一次 = 取消稍后看；仍留在收藏里就把 tag 清掉
        await db.favoriteDao.setTag(hit.id, null);
        return false;
      }
      await db.favoriteDao.setTag(hit.id, laterTag);
      return true;
    }
    await db.favoriteDao.add(Favorite(
      id: m.id,
      title: m.title,
      url: m.url,
      sourceKind: m.sourceKind,
      sourceId: m.sourceId,
      poster: m.poster,
      tag: laterTag,
      addedAt: now,
    ));
    return true;
  }

  Future<List<Favorite>> listWatchLater({int limit = 200}) async {
    final List<Favorite> all = await db.favoriteDao.all(tag: laterTag);
    return all.length > limit ? all.sublist(0, limit) : all;
  }

  // ── 追番（favorites.tag = 'follow'）────────────────────

  /// 收藏并标成追番。已经有这行就只改 tag（追番优先于普通收藏）。
  ///
  /// 返回 true = 现在在追，false = 刚取消追番（行还在，回到普通收藏）。
  Future<bool> markFollow(LibraryMedia m) async {
    final Favorite? hit = await _favoriteByUrl(m.url);
    if (hit != null) {
      if (hit.tag == followTag) {
        await db.favoriteDao.setTag(hit.id, null);
        return false;
      }
      await db.favoriteDao.setTag(hit.id, followTag);
      return true;
    }
    await db.favoriteDao.add(Favorite(
      id: m.id,
      title: m.title,
      url: m.url,
      sourceKind: m.sourceKind,
      sourceId: m.sourceId,
      poster: m.poster,
      tag: followTag,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return true;
  }

  /// 按 id 取消追番：只清 tag，不删行（取消后回到普通收藏）
  Future<void> unfollow(String id) => db.favoriteDao.setTag(id, null);

  Future<List<Favorite>> listFollowing({int limit = 200}) async {
    final List<Favorite> all = await db.favoriteDao.all(tag: followTag);
    return all.length > limit ? all.sublist(0, limit) : all;
  }

  Future<bool> isFollowing(String url) async =>
      (await _favoriteByUrl(url))?.tag == followTag;

  // ── 历史 ────────────────────────────────────────────────

  /// 写一次进度。增量与"看完清位置"的规则全在 [HistoryDao.record] 里，
  /// 这里只补两件事：没传 duration 就沿用旧行，roomCode 塞进 extra。
  Future<void> upsertHistory(
    LibraryMedia m,
    Duration pos, {
    Duration? duration,
    String? roomCode,
    String? seriesId,
  }) async {
    final String id = m.id;
    final History? old = await db.historyDao.byId(id);
    final double dur = duration != null
        ? duration.inMilliseconds / 1000.0
        : (old?.duration ?? 0);
    final String? extra = roomCode == null || roomCode.isEmpty
        ? old?.extra
        : jsonEncode(<String, Object?>{'room': roomCode});
    await db.historyDao.record(
      id: id,
      title: m.title,
      url: m.url,
      sourceKind: m.sourceKind,
      sourceId: m.sourceId,
      poster: m.poster,
      position: pos.inMilliseconds / 1000.0,
      duration: dur,
      episodeIndex: m.episodeIndex,
      seriesId: seriesId,
    );
    if (extra != null && extra.isNotEmpty) {
      await (db.update(db.historyTable)
            ..where(($HistoryTableTable t) => t.id.equals(id)))
          .write(HistoryTableCompanion(extra: Value<String?>(extra)));
    }
  }

  Future<List<History>> listHistory({int limit = 100}) =>
      db.historyDao.recent(limit: limit);

  Future<void> clearHistory() => db.historyDao.clearAll();

  Future<void> removeHistory(String id) => db.historyDao.deleteById(id);

  // ── 内部 ────────────────────────────────────────────────

  Future<Favorite?> _favoriteByUrl(String url) {
    return (db.select(db.favorites)
          ..where(($FavoritesTable t) => t.url.equals(url))
          ..limit(1))
        .getSingleOrNull();
  }
}
