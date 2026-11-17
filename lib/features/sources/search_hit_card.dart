import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../data/sources/source_service.dart';

/// 搜索结果卡片（F9 评分渲染的唯一出口）。
///
/// 抽成独立 widget 而不是留在 SourcesPage 里，是因为「有评分时源名后面要带
/// `4.0★`」这条分支在真机上很难触发（内置演示源 kind=direct 永远 0 命中），
/// 抽出来之后可以用 widget 测试直接喂 SearchHit 断言星星渲染。
class SearchHitCard extends StatelessWidget {
  const SearchHitCard({
    super.key,
    required this.hit,
    this.score,
    this.onTap,
  });

  final SearchHit hit;

  /// 该源的本地评分（1..5）；没评过就是 null，此时不显示星级。
  final int? score;

  final VoidCallback? onTap;

  /// 源名 + 评分 + 备注，形如 `演示源 4.0★ · 高清`。
  String get subtitleText {
    final String star = score == null ? '' : ' ${score!.toDouble().toStringAsFixed(1)}★';
    final String remarks = hit.remarks.isEmpty ? '' : ' · ${hit.remarks}';
    return '${hit.sourceName}$star$remarks';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.stroke),
          boxShadow: AppShadow.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: hit.poster.isEmpty
                  ? Container(
                      color: AppColors.surface3,
                      child: Icon(Icons.movie_outlined,
                          color: AppColors.textDim),
                    )
                  : Image.network(
                      hit.poster,
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                          Container(
                        color: AppColors.surface3,
                        child: Icon(Icons.movie_outlined,
                            color: AppColors.textDim),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hit.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.card,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sub.copyWith(color: AppColors.textDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}