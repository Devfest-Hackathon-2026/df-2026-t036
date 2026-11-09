import 'package:flutter/material.dart';

/// A slow border glow that runs only while an interactive card is hovered.
class CardHoverGlow extends StatefulWidget {
  const CardHoverGlow({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.enabled = true,
  });

  final Widget child;
  final Color color;
  final double radius;
  final bool enabled;

  @override
  State<CardHoverGlow> createState() => _CardHoverGlowState();
}

class _CardHoverGlowState extends State<CardHoverGlow>
    with TickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    reverseDuration: const Duration(milliseconds: 450),
  );
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _hovered = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant CardHoverGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  void _updateAnimation() {
    final active = _hovered && widget.enabled;
    if (_reduceMotion) {
      _fade.value = active ? 1 : 0;
      _pulse.stop();
      _pulse.value = 0;
    } else if (active) {
      _fade.forward();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _fade.reverse();
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _hovered = true;
      _updateAnimation();
    },
    onExit: (_) {
      _hovered = false;
      _updateAnimation();
    },
    child: AnimatedBuilder(
      animation: Listenable.merge([_fade, _pulse]),
      child: widget.child,
      builder: (context, child) {
        final fade = Curves.easeInOut.transform(_fade.value);
        final pulse = Curves.easeInOutSine.transform(_pulse.value);
        final strength = fade * (0.65 + 0.35 * pulse);
        final radius = BorderRadius.circular(widget.radius);
        return Container(
          transform: Matrix4.translationValues(
            0,
            _reduceMotion ? 0 : -2 * fade,
            0,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.38 * strength),
                blurRadius: 10 + 6 * pulse,
                spreadRadius: 1.5 * strength,
              ),
            ],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: widget.color.withValues(alpha: 0.85 * strength),
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
    ),
  );
}
