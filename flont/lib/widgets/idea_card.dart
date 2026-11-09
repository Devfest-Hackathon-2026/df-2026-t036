import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'card_hover_glow.dart';

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
    this.sketchStyle = false,
    this.statusLabel,
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

  // Opt in on the timeline; existing history and slot cards keep their layout.
  final bool sketchStyle;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    if (sketchStyle) {
      return CardHoverGlow(
        color: AppColors.borderFor(backgroundColor ?? AppColors.main),
        radius: 12,
        enabled: onTap != null || onPinPressed != null,
        child: _SketchIdeaCard(card: this),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final local = date.toLocal();
    final label =
        '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
    return CardHoverGlow(
      color: backgroundColor == null
          ? borderColor ?? AppColors.outline
          : AppColors.borderFor(backgroundColor!),
      radius: AppTheme.cardRadius,
      enabled: onTap != null || onPinPressed != null,
      child: Card(
        color: backgroundColor,
        shape: borderColor == null
            ? null
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                side: BorderSide(
                  color: backgroundColor == null
                      ? borderColor!
                      : AppColors.borderFor(backgroundColor!),
                  width: 1.5,
                ),
              ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.transparent,
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
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A paper-like timeline presentation using the existing idea actions and data.
class _SketchIdeaCard extends StatefulWidget {
  const _SketchIdeaCard({required this.card});
  final IdeaCard card;

  @override
  State<_SketchIdeaCard> createState() => _SketchIdeaCardState();
}

class _SketchIdeaCardState extends State<_SketchIdeaCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final text = Theme.of(context).textTheme;
    final accent = card.borderColor ?? AppColors.main;
    final date = card.date.toLocal();
    final dateLabel =
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: AppColors.borderFor(card.backgroundColor ?? AppColors.main),
      ),
    );
    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(
        0,
        reduceMotion ? 0 : (_pressed ? 1 : 0),
        0,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.sub.withValues(alpha: _pressed ? 0.025 : 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: card.onTap,
          hoverColor: Colors.transparent,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          splashColor: AppColors.main.withValues(alpha: 0.25),
          highlightColor: AppColors.main.withValues(alpha: 0.12),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: card.showBookmark ? 44 : 0,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 3,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          if (card.statusLabel != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                card.statusLabel!,
                                style: text.labelSmall?.copyWith(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else
                            const SizedBox(height: 18),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      card.title,
                      style: text.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 1.6,
                        color: AppColors.sub,
                      ),
                    ),
                    if (card.tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in card.tags)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color.lerp(
                                  AppColors.surface,
                                  AppColors.main,
                                  0.28,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text(
                                  '#$tag',
                                  style: text.labelMedium?.copyWith(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: AppColors.outline),
                    const SizedBox(height: 12),
                    Text(
                      dateLabel,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (card.showBookmark)
                Positioned(
                  top: 0,
                  right: 12,
                  child: Semantics(
                    selected: card.pinned,
                    child: SizedBox(
                      width: 48,
                      height: 52,
                      child: CustomPaint(
                        painter: _BookmarkRibbonPainter(pinned: card.pinned),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: card.onPinPressed == null ? () {} : null,
                          child: IconButton(
                            tooltip: card.pinned ? 'ブックマークを解除' : 'ブックマークに保存',
                            onPressed: card.onPinPressed,
                            iconSize: 20,
                            color: AppColors.sub,
                            disabledColor: AppColors.muted.withValues(
                              alpha: 0.45,
                            ),
                            icon: Icon(
                              card.pinned
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A narrow paper bookmark with a small V-shaped cut at the bottom.
class _BookmarkRibbonPainter extends CustomPainter {
  const _BookmarkRibbonPainter({required this.pinned});
  final bool pinned;

  @override
  void paint(Canvas canvas, Size size) {
    final ribbon = Path()
      ..moveTo(7, 0)
      ..lineTo(size.width - 7, 0)
      ..lineTo(size.width - 7, size.height - 6)
      ..lineTo(size.width / 2, size.height - 13)
      ..lineTo(7, size.height - 6)
      ..close();
    canvas.drawPath(
      ribbon,
      Paint()..color = pinned ? AppColors.main : AppColors.background,
    );
    canvas.drawPath(
      ribbon,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BookmarkRibbonPainter oldDelegate) =>
      oldDelegate.pinned != pinned;
}
