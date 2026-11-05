
import 'dart:math' as math;
import 'package:flutter/material.dart';

class ProfileCard extends StatefulWidget {
  final String nickname;
  final String? backgroundImage;
  final String? avatarImage;
  final int ideaCount;
  final int drawingCount;
  final int likeCount;

  const ProfileCard({
    super.key,
    required this.nickname,
    this.backgroundImage,
    this.avatarImage,
    this.ideaCount = 0,
    this.drawingCount = 0,
    this.likeCount = 0,
  });

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  void _flipCard() {
    if (_controller.isAnimating) return;

    if (_controller.value < 0.5) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flipCard,
      child: SizedBox(
        width: 320,
        height: 500,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final angle = _controller.value * math.pi;
            final isBack = angle >= math.pi / 2;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              child: isBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(math.pi),
                      child: _buildCard(isBack: true),
                    )
                  : _buildCard(isBack: false),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard({required bool isBack}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: isBack
                    ? _buildStats(colorScheme)
                    : _buildBackground(colorScheme),
              ),
            ),

            // アイコンを上部エリアに少し重ねる
            Transform.translate(
              offset: const Offset(0, -24),
              child: Row(
                children: [
                  _buildAvatar(colorScheme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.nickname,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(ColorScheme colors) {
    if (widget.backgroundImage != null) {
      return Image.asset(
        widget.backgroundImage!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _backgroundPlaceholder(colors);
        },
      );
    }

    return _backgroundPlaceholder(colors);
  }

  Widget _backgroundPlaceholder(ColorScheme colors) {
    return Container(
      width: double.infinity,
      color: colors.primaryContainer,
      child: Center(
        child: Icon(
          Icons.palette_outlined,
          size: 72,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme colors) {
    return CircleAvatar(
      radius: 42,
      backgroundColor: colors.surface,
      child: CircleAvatar(
        radius: 38,
        backgroundColor: colors.secondaryContainer,
        backgroundImage: widget.avatarImage != null
            ? AssetImage(widget.avatarImage!)
            : null,
        child: widget.avatarImage == null
            ? Icon(
                Icons.person_outline,
                size: 42,
                color: colors.onSecondaryContainer,
              )
            : null,
      ),
    );
  }

  Widget _buildStats(ColorScheme colors) {
    return Container(
      width: double.infinity,
      color: colors.surfaceContainerHighest,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statRow(Icons.lightbulb_outline, 'アイデア数', widget.ideaCount),
          const Divider(),
          _statRow(Icons.brush_outlined, '描いた数', widget.drawingCount),
          const Divider(),
          _statRow(Icons.favorite_outline, 'もらったいいね', widget.likeCount),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, int value) {
    return Row(
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          _formatCount(value),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }

  String _formatCount(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }
}
