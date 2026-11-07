import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/page_layout.dart';
import 'package:flutter/gestures.dart';
import 'ideas_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.artworkTitles = const []});

  // 実データの接続時は受信作品のタイトルを渡せる。
  final List<String> artworkTitles;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _controller = PageController();
  int _page = 0;
  final _gestureKey = GlobalKey();
  int? _pointer;
  Offset? _origin;
  double _rotationX = 0;

  // アイデア枠と同じ計算で、指の位置と縦方向の移動から傾きを決める。
  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _origin == null) return;
    if ((event.localPosition - _origin!).distance < 4) return;
    final size = _gestureKey.currentContext?.size;
    if (size == null || size.isEmpty) return;
    final fingerY = (event.localPosition.dy / size.height * 2 - 1).clamp(
      -1.0,
      1.0,
    );
    final dragY = (event.localPosition.dy - _origin!.dy) / size.height;
    setState(
      () => _rotationX = (fingerY * 0.035 + dragY * 0.08).clamp(-0.10, 0.10),
    );
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    setState(() {
      _pointer = null;
      _origin = null;
      _rotationX = 0;
    });
  }

  Widget _buildCarousel(List<String> titles) {
    return Listener(
      key: _gestureKey,
      onPointerDown: (event) {
        if (_pointer != null) return;
        setState(() {
          _pointer = event.pointer;
          _origin = event.localPosition;
        });
      },
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final page = _controller.hasClients
              ? _controller.page ?? _page.toDouble()
              : _page.toDouble();
          final moving = (page - page.roundToDouble()).abs() > 0.0001;
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                ...ScrollConfiguration.of(context).dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
            child: PageView.builder(
              controller: _controller,
              physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
              itemCount: titles.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) {
                final weight = (1.0 - (page - index).abs()).clamp(0.0, 1.0);
                final offset = (page - index).clamp(-1.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 0,
                  ),
                  child: TiltCard(
                    key: ValueKey('inbox-tilt-$index'),
                    rotationX: _rotationX * weight,
                    rotationY: -offset * 0.16,
                    isDragging: (_pointer != null || moving) && weight > 0,
                    child: IdeaSlotCard(
                      slotNumber: index + 1,
                      label: '受信作品 ${index + 1}',
                      title: titles[index],
                      subtitle: '届いたイラスト',
                      icon: Icons.image_outlined,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // デバッグプレビューでだけ複数作品の配置を確認する。
  List<String> get _titles =>
      kDebugMode && const bool.fromEnvironment('DEV_PREVIEW')
      ? const ['夜明けを待つ庭', '旅する小さな天文台', '月明かりと青い花']
      : widget.artworkTitles;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _titles.length) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  void _move(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    final titles = _titles;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        final headingGap = compact ? 8.0 : 16.0;
        // 下部操作は本文内に置き、固定せずカードと一緒にスクロールさせる。
        return SingleChildScrollView(
          padding: layout.insets,
          child: Center(
            child: ConstrainedBox(
              // 外側の余白も含めた全体幅を他の画面にそろえる。
              constraints: BoxConstraints(maxWidth: layout.contentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('受信箱', style: Theme.of(context).textTheme.headlineSmall),
                  SizedBox(height: headingGap),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: layout.contentWidth,
                      ),
                      // 幅に合わせて高さを決め、横3・縦4を維持する。
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: titles.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 0,
                                ),
                                child: IdeaSlotCard(
                                  slotNumber: 1,
                                  label: '受信作品',
                                  emptyText: 'まだ作品は届いていません',
                                  emptyIcon: Icons.inbox_outlined,
                                ),
                              )
                            : _buildCarousel(titles),
                      ),
                    ),
                  ),
                  // 一作品の場合は切り替え操作を表示しない。
                  if (titles.length > 1) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: '前の作品',
                          onPressed: _page == 0 ? null : () => _move(_page - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text('${_page + 1} / ${titles.length}'),
                        ),
                        IconButton.filledTonal(
                          tooltip: '次の作品',
                          onPressed: _page == titles.length - 1
                              ? null
                              : () => _move(_page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
