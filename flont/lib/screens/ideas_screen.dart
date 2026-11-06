import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _developmentPreview = bool.fromEnvironment('DEV_PREVIEW');

class IdeasScreen extends StatefulWidget {
  const IdeasScreen({super.key});

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  static const _previewTitles = ['夜明けを待つ庭', '旅する小さな天文台'];
  static const _slotCount = 5;

  final _pageController = PageController();
  final _carouselGestureKey = GlobalKey();
  int _currentPage = 0;
  int? _activePointer;
  Offset? _touchOrigin;
  bool _hasDragged = false;
  double _rotationX = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _moveToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    setState(() {
      _activePointer = event.pointer;
      _touchOrigin = event.localPosition;
      _hasDragged = false;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final origin = _touchOrigin;
    if (origin == null) return;
    if (!_hasDragged && (event.localPosition - origin).distance < 4) return;
    setState(() {
      _hasDragged = true;
      _updateRotation(event.localPosition);
    });
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    setState(() {
      _activePointer = null;
      _touchOrigin = null;
      _hasDragged = false;
      _rotationX = 0;
    });
  }

  void _updateRotation(Offset position) {
    final size = _carouselGestureKey.currentContext?.size;
    final origin = _touchOrigin;
    if (size == null || origin == null || size.isEmpty) return;

    final fingerY = (position.dy / size.height * 2 - 1).clamp(-1.0, 1.0);
    final dragY = (position.dy - origin.dy) / size.height;
    _rotationX = (fingerY * 0.035 + dragY * 0.08).clamp(-0.10, 0.10);
  }

  @override
  Widget build(BuildContext context) {
    final preview = kDebugMode && _developmentPreview;
    final occupiedCount = preview ? _previewTitles.length : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        final scrollBehavior = ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            ...ScrollConfiguration.of(context).dragDevices,
            PointerDeviceKind.mouse,
          },
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(16, compact ? 12 : 20, 16, 4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'アイデア枠',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '掲載中 $occupiedCount / $_slotCount',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 16),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Listener(
                          key: _carouselGestureKey,
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _onPointerDown,
                          onPointerMove: _onPointerMove,
                          onPointerUp: _onPointerEnd,
                          child: AnimatedBuilder(
                            animation: _pageController,
                            builder: (context, child) {
                              final page = _pageController.hasClients
                                  ? _pageController.page ??
                                        _currentPage.toDouble()
                                  : _currentPage.toDouble();
                              final pageIsMoving =
                                  (page - page.roundToDouble()).abs() > 0.0001;
                              return ScrollConfiguration(
                                behavior: scrollBehavior,
                                child: PageView.builder(
                                  key: const ValueKey('idea-carousel'),
                                  controller: _pageController,
                                  physics: const PageScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  itemCount: _slotCount,
                                  onPageChanged: (page) => setState(() {
                                    _currentPage = page;
                                  }),
                                  itemBuilder: (context, index) {
                                    final title =
                                        preview && index < occupiedCount
                                        ? _previewTitles[index]
                                        : null;
                                    final distance = (page - index).abs();
                                    final tiltWeight = (1.0 - distance)
                                        .clamp(0.0, 1.0)
                                        .toDouble();
                                    final pageOffset = (page - index)
                                        .clamp(-1.0, 1.0)
                                        .toDouble();
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: _TiltCard(
                                        key: ValueKey(
                                          'idea-tilt-card-${index + 1}',
                                        ),
                                        rotationX: _rotationX * tiltWeight,
                                        rotationY: -pageOffset * 0.16,
                                        isDragging:
                                            (_activePointer != null ||
                                                pageIsMoving) &&
                                            tiltWeight > 0,
                                        child: _IdeaSlotCard(
                                          key: ValueKey(
                                            'idea-slot-${index + 1}',
                                          ),
                                          slotNumber: index + 1,
                                          title: title,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        tooltip: '前のアイデア',
                        onPressed: _currentPage == 0
                            ? null
                            : () => _moveToPage(_currentPage - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '${_currentPage + 1} / $_slotCount',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: '次のアイデア',
                        onPressed: _currentPage == _slotCount - 1
                            ? null
                            : () => _moveToPage(_currentPage + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TiltCard extends StatelessWidget {
  const _TiltCard({
    super.key,
    required this.child,
    required this.rotationX,
    required this.rotationY,
    required this.isDragging,
  });

  final Widget child;
  final double rotationX;
  final double rotationY;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.003)
      ..rotateX(rotationX)
      ..rotateY(rotationY);

    return AnimatedContainer(
      key: key == null
          ? null
          : ValueKey('${(key as ValueKey).value}-transform'),
      duration: isDragging ? Duration.zero : const Duration(milliseconds: 440),
      curve: isDragging ? Curves.linear : Curves.easeOutBack,
      transform: transform,
      transformAlignment: Alignment.center,
      child: child,
    );
  }
}

class _IdeaSlotCard extends StatelessWidget {
  const _IdeaSlotCard({super.key, required this.slotNumber, this.title});

  final int slotNumber;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isOccupied = title != null;

    return Card(
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isOccupied
                      ? colors.primaryContainer
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    isOccupied ? Icons.lightbulb_outline : Icons.add,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '枠 $slotNumber',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title ?? '空き枠',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isOccupied) ...[
                      const SizedBox(height: 4),
                      Text(
                        'TL掲載中',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
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
