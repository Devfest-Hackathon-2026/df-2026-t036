import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// タイトル・ブックマーク・タグ・日付をまとめ、内容に合わせて高さを調整するカード。
class IdeaCard extends StatelessWidget {
  const IdeaCard({
    super.key,
    required this.title,
    required this.date,
    this.tags = const [],
    this.backgroundColor,
    this.borderColor,
    this.pinned = false,
    this.showBookmark = true,
    this.onPinPressed,
    this.onTap,
  });

  // 状態ごとの背景と外枠は共通テーマのアクセントを参照して指定する。
  final Color? backgroundColor;
  final Color? borderColor;
  final String title;
  final DateTime date;
  final List<String> tags;
  // 自分のお題枠ではブックマーク操作を表示しない。
  final bool showBookmark;
  final bool pinned;
  final VoidCallback? onPinPressed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final local = date.toLocal();
    final label =
        '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
    return Card(
      color: backgroundColor,
      shape: borderColor == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              side: BorderSide(color: borderColor!, width: 1.5),
            ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ブックマークをタイトル横へ置き、上部だけの余白をなくす。
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (showBookmark)
                    IconButton(
                      tooltip: pinned ? 'ブックマークを解除' : 'ブックマークに保存',
                      onPressed: onPinPressed,
                      color: colors.primary,
                      icon: Icon(
                        pinned ? Icons.bookmark : Icons.bookmark_border,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // タグと日付を同じ行に置き、タグだけを残り幅で折り返す。
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '#$tag',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: colors.onPrimaryContainer,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
