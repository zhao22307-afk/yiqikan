import 'player_controller.dart';

/// 从房主的 `media` 帧里取出整条线路的片单。
///
/// 第 38 轮：房主换片源时会把 `urls` / `titles` 一起发过来。
/// 旧版本房主（或第三方客户端）不发这两个字段，这时返回空表 ——
/// 客人只切当前这一条，不报错、也不清掉已有片单之外的东西。
///
/// `titles` 比 `urls` 短时按「第 N 集」兜底；`urls` 里的空串直接跳过。
List<PlayerMedia> playlistFromMediaFrame(Map<String, dynamic> f) {
  final Object? rawUrls = f['urls'];
  if (rawUrls is! List || rawUrls.isEmpty) return <PlayerMedia>[];
  final Object? rawTitles = f['titles'];
  final List<dynamic>? titles = rawTitles is List ? rawTitles : null;
  final String kind = (f['sourceKind'] ?? 'room').toString();
  final String? sourceId = f['sourceId']?.toString();
  final List<PlayerMedia> out = <PlayerMedia>[];
  for (int i = 0; i < rawUrls.length; i++) {
    final String u = (rawUrls[i] ?? '').toString();
    if (u.isEmpty) continue;
    final String t = (titles != null && i < titles.length)
        ? titles[i].toString()
        : '第 ${i + 1} 集';
    out.add(PlayerMedia(
      id: u,
      title: t,
      url: u,
      sourceKind: kind,
      sourceId: sourceId,
    ));
  }
  return out;
}
