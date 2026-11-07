import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum ArtworkAction { like, save }

class ArtworkActions extends StatefulWidget {
  const ArtworkActions({
    super.key,
    required this.child,
    required this.liked,
    this.onLike,
    this.onSave,
  });
  final Widget child;
  final bool liked;
  final VoidCallback? onLike;
  final VoidCallback? onSave;

  @override
  State<ArtworkActions> createState() => _ArtworkActionsState();
}

class _ArtworkActionsState extends State<ArtworkActions> {
  OverlayEntry? _menu;
  ArtworkAction? _selected;
  List<Offset> _centers = [];
  RenderBox? _overlayBox;

  VoidCallback? _callback(ArtworkAction action) => switch (action) {
    ArtworkAction.like => widget.onLike,
    ArtworkAction.save => widget.onSave,
  };
  String _label(ArtworkAction action) => switch (action) {
    ArtworkAction.like => widget.liked ? 'いいね済み' : 'いいね',
    ArtworkAction.save => '画像保存',
  };
  IconData _icon(ArtworkAction action) => switch (action) {
    ArtworkAction.like => widget.liked ? Icons.favorite : Icons.favorite_border,
    ArtworkAction.save => Icons.download_outlined,
  };

  void _close() {
    final menu = _menu;
    _menu = null;
    if (menu != null) {
      void remove() {
        menu.remove();
        menu.dispose();
      }

      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => remove());
      } else {
        remove();
      }
    }
    _selected = null;
  }

  void _start(LongPressStartDetails details) {
    _close();
    final overlay = Overlay.of(context, rootOverlay: true);
    _overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final origin = _overlayBox!.globalToLocal(details.globalPosition);
    final size = _overlayBox!.size;
    final padding = MediaQuery.paddingOf(context);
    final x = origin.dx.clamp(80.0, size.width - 80.0);
    final below = origin.dy < padding.top + 180;
    final y = (origin.dy + (below ? 88 : -80)).clamp(
      padding.top + 76,
      size.height - padding.bottom - 84,
    );
    _centers = [Offset(x - 40, y), Offset(x + 40, y)];
    _menu = OverlayEntry(
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ),
                for (final action in ArtworkAction.values)
                  Positioned(
                    left: _centers[action.index].dx - 40,
                    top: _centers[action.index].dy - 28,
                    child: SizedBox(
                      width: 80,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            key: ValueKey('quick-action-${action.name}'),
                            duration: const Duration(milliseconds: 100),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _selected == action
                                  ? colors.primary
                                  : colors.surface,
                              border: Border.all(
                                color: _selected == action
                                    ? colors.primary
                                    : colors.outlineVariant,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              _icon(action),
                              color: _callback(action) == null
                                  ? colors.onSurfaceVariant.withValues(
                                      alpha: 0.4,
                                    )
                                  : _selected == action
                                  ? colors.onPrimary
                                  : colors.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              child: Text(
                                _label(action),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_menu!);
  }

  void _move(Offset globalPosition) {
    if (_menu == null) return;
    final position = _overlayBox!.globalToLocal(globalPosition);
    ArtworkAction? selected;
    for (final action in ArtworkAction.values) {
      if (_callback(action) != null &&
          (position - _centers[action.index]).distance <= 36) {
        selected = action;
      }
    }
    if (_selected != selected) {
      _selected = selected;
      _menu!.markNeedsBuild();
    }
  }

  @override
  void didUpdateWidget(covariant ArtworkActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onLike == null && widget.onSave == null) {
      _close();
    }
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onLike != null || widget.onSave != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: const ValueKey('artwork-long-press'),
          onLongPressStart: enabled ? _start : null,
          onLongPressMoveUpdate: enabled
              ? (details) => _move(details.globalPosition)
              : null,
          onLongPressEnd: enabled
              ? (details) {
                  _move(details.globalPosition);
                  final action = _selected;
                  _close();
                  if (action != null) _callback(action)?.call();
                }
              : null,
          onLongPressCancel: _close,
          child: widget.child,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in ArtworkAction.values)
              OutlinedButton.icon(
                key: ValueKey('artwork-action-${action.name}'),
                onPressed: _callback(action),
                icon: Icon(_icon(action)),
                label: Text(_label(action)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '長押ししてアイコンへスライドしても操作できます',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
