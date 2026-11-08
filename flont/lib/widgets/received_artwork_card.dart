import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Presentation only: read status is supplied by the inbox.
class ReceivedArtworkCard extends StatelessWidget {
  const ReceivedArtworkCard({
    super.key,
    required this.title,
    required this.label,
    required this.isUnread,
    this.openingProgress = 0,
  }) : assert(openingProgress >= 0 && openingProgress <= 1);

  final String title;
  final String label;
  final bool isUnread;

  /// Visual progress only: 0 is sealed, 1 is open. The caller owns animation
  /// timing and navigation; read status must not be used as animation state.
  final double openingProgress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnread ? AppColors.main : AppColors.outline,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sub.withValues(alpha: isUnread ? 0.06 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: CustomPaint(
        painter: const _EnvelopeBodyPainter(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(-math.pi * openingProgress),
                  child: const CustomPaint(painter: _EnvelopeFlapPainter()),
                ),
              ),
            ),
            Padding(
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
                          style: text.labelMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isUnread
                              ? AppColors.main
                              : AppColors.background,
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
                    child: Opacity(
                      opacity: (1 - openingProgress * 4).clamp(0.0, 1.0),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: isUnread ? AppColors.main : AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isUnread
                                ? AppColors.surface
                                : AppColors.outline,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.sub.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          isUnread
                              ? Icons.auto_awesome_rounded
                              : Icons.drafts_outlined,
                          size: 26,
                          color: AppColors.sub,
                        ),
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
                    'タップして手紙を開く',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: AppColors.muted),
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

/// Static envelope body, separate from the moving flap.
class _EnvelopeBodyPainter extends CustomPainter {
  const _EnvelopeBodyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
    );
    final crease = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final lowerFold = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.24, size.height * 0.82)
      ..moveTo(size.width, size.height)
      ..lineTo(size.width * 0.76, size.height * 0.82);
    canvas.drawPath(lowerFold, crease);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EnvelopeBodyPainter oldDelegate) => false;
}

/// Independent white flap; rotated around its top edge by the parent.
class _EnvelopeFlapPainter extends CustomPainter {
  const _EnvelopeFlapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
    );
    final fold = Offset(size.width / 2, size.height * 0.37);
    final flap = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.10)
      ..lineTo(fold.dx, fold.dy)
      ..lineTo(0, size.height * 0.10)
      ..close();
    canvas.drawShadow(flap, AppColors.sub.withValues(alpha: 0.08), 1.5, false);
    canvas.drawPath(flap, Paint()..color = AppColors.surface);
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.10)
        ..lineTo(fold.dx, fold.dy)
        ..lineTo(size.width, size.height * 0.10),
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EnvelopeFlapPainter oldDelegate) => false;
}
