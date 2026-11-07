import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TimelineTagBar extends StatefulWidget {
  const TimelineTagBar({
    super.key,
    required this.tags,
    required this.selectedTag,
    required this.onSelected,
  });
  final List<String> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelected;
  @override
  State<TimelineTagBar> createState() => _TimelineTagBarState();
}

class _TimelineTagBarState extends State<TimelineTagBar> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canNext = false;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateButtons);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateButtons() {
    if (!mounted ||
        !_controller.hasClients ||
        !_controller.position.hasContentDimensions) {
      return;
    }
    final back = _controller.offset > 1;
    final next = _controller.offset < _controller.position.maxScrollExtent - 1;
    if (back != _canBack || next != _canNext) {
      setState(() {
        _canBack = back;
        _canNext = next;
      });
    }
  }

  void _move(int direction) {
    final target =
        (_controller.offset +
                direction * _controller.position.viewportDimension * 0.75)
            .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateButtons());
    return Row(
      children: [
        IconButton(
          tooltip: '前のタグ',
          onPressed: _canBack ? () => _move(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                ...ScrollConfiguration.of(context).dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
            child: SingleChildScrollView(
              key: const ValueKey('timeline-tag-scroll'),
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = -1; index < widget.tags.length; index++) ...[
                    if (index >= 0) const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final tag = index < 0 ? null : widget.tags[index];
                        final selected = widget.selectedTag == tag;
                        final background = selected
                            ? AppColors.sub
                            : index < 0
                            ? AppColors.main
                            : AppColors.tagBackgrounds[index %
                                  AppColors.tagBackgrounds.length];
                        // Use the text's natural width and height, including CJK glyphs.
                        return Semantics(
                          key: ValueKey('timeline-tag-${tag ?? 'all'}'),
                          selected: selected,
                          button: true,
                          child: Material(
                            color: background,
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: selected
                                    ? AppColors.sub
                                    : AppColors.outline,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: () =>
                                  widget.onSelected(selected ? null : tag),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    tag == null ? 'すべて' : '#$tag',
                                    softWrap: false,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          height: 1.5,
                                          color: selected
                                              ? AppColors.background
                                              : AppColors.sub,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '次のタグ',
          onPressed: _canNext ? () => _move(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
