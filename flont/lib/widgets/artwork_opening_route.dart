import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'received_artwork_card.dart';

/// Builds the destination immediately so image loading overlaps the opening.
/// Timing belongs to this route; the envelope remains a presentation widget.
class ArtworkOpeningRoute extends PageRouteBuilder<bool> {
  ArtworkOpeningRoute({
    required WidgetBuilder builder,
    required Rect sourceRect,
    required String title,
    required String label,
    required bool isUnread,
    bool reduceMotion = false,
  }) : super(
         opaque: true,
         transitionDuration: reduceMotion
             ? Duration.zero
             : const Duration(milliseconds: 900),
         reverseTransitionDuration: reduceMotion
             ? Duration.zero
             : const Duration(milliseconds: 180),
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (animation.status == AnimationStatus.reverse) {
             return FadeTransition(opacity: animation, child: child);
           }
           if (animation.isCompleted) return child;
           return _OpeningScene(
             progress: animation.value,
             sourceRect: sourceRect,
             title: title,
             label: label,
             isUnread: isUnread,
             child: child,
           );
         },
       );
}

class _OpeningScene extends StatelessWidget {
  const _OpeningScene({
    required this.progress,
    required this.sourceRect,
    required this.title,
    required this.label,
    required this.isUnread,
    required this.child,
  });

  final double progress;
  final Rect sourceRect;
  final String title;
  final String label;
  final bool isUnread;
  final Widget child;

  double phase(double begin, double end) => Curves.easeInOutCubic.transform(
    ((progress - begin) / (end - begin)).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    final opening = phase(0, 0.30);
    final pulling = phase(0.25, 0.60);
    final covering = phase(0.60, 0.90);
    final reveal = phase(0.90, 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Offset.zero & constraints.biggest;
        final paperStart = sourceRect.deflate(14);
        final extracted = paperStart.shift(
          Offset(0, -sourceRect.height * 0.85 * pulling),
        );
        final paper = Rect.lerp(extracted, screen, covering)!;
        final envelopeCard = ReceivedArtworkCard(
          title: title,
          label: label,
          isUnread: isUnread,
          openingProgress: opening,
        );
        final envelope = Positioned.fromRect(
          rect: sourceRect,
          child: Opacity(
            opacity: 1 - covering,
            child: sourceRect.width < 240
                ? FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 240,
                      height: 320,
                      child: envelopeCard,
                    ),
                  )
                : envelopeCard,
          ),
        );
        final letter = Positioned.fromRect(
          rect: paper,
          child: Opacity(
            opacity: (pulling > 0 ? 1.0 : 0.0) * (1 - reveal),
            child: Transform.rotate(
              angle: -0.035 * pulling * (1 - covering),
              child: DecoratedBox(
                key: const ValueKey('opening-letter'),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16 * (1 - covering)),
                  border: covering < 1
                      ? Border.all(color: AppColors.outline)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Opacity(
                  opacity: 1 - covering,
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 36,
                      color: AppColors.sub.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // Kept laid out for image loading and decode; gated separately from read receipts.
            ExcludeFocus(
              excluding: progress < 1,
              child: IgnorePointer(
                ignoring: progress < 1,
                child: Opacity(opacity: progress >= 0.90 ? 1 : 0, child: child),
              ),
            ),
            IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 1 - reveal,
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      ColoredBox(
                        color: AppColors.background.withValues(
                          alpha: phase(0, 0.15),
                        ),
                      ),
                      envelope,
                      if (progress < 0.60)
                        ClipRect(
                          clipper: _LetterMouth(sourceRect.top),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [letter],
                          ),
                        )
                      else
                        letter,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Only the portion above the envelope mouth is visible while pulling it out.
class _LetterMouth extends CustomClipper<Rect> {
  const _LetterMouth(this.bottom);
  final double bottom;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width, bottom.clamp(0.0, size.height));
  @override
  bool shouldReclip(covariant _LetterMouth oldClipper) =>
      oldClipper.bottom != bottom;
}
