import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Presentation only: read status is supplied by the inbox.
class ReceivedArtworkCard extends StatelessWidget {
  const ReceivedArtworkCard({
    super.key,
    required this.title,
    required this.label,
    required this.isUnread,
  });

  final String title;
  final String label;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isUnread ? AppColors.main : AppColors.outline,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sub.withValues(alpha: isUnread ? 0.10 : 0.06),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: AppColors.muted),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: isUnread ? AppColors.main : AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      isUnread ? '未読' : '既読',
                      style: text.labelSmall?.copyWith(
                        color: isUnread ? AppColors.sub : AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isUnread ? AppColors.main : AppColors.background,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  size: 32,
                  color: AppColors.sub,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              flex: 3,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge?.copyWith(
                  fontSize: 19,
                  height: 1.5,
                  color: AppColors.sub,
                ),
              ),
            ),
            const Spacer(),
            const SizedBox(height: 16),
            Text(
              'タップして作品を開く',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
