import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'idea_composer_screen.dart';
import 'idea_detail_screen.dart';
import '../theme/app_theme.dart';

const _developmentPreview = bool.fromEnvironment('DEV_PREVIEW');

class IdeasScreen extends StatefulWidget {
  const IdeasScreen({
    super.key,
    this.apiBaseUrl = 'http://localhost:8080',
    this.authenticated = false,
  });

  final String apiBaseUrl;
  final bool authenticated;

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  static const _previewTitles = ['夜明けを待つ庭', '旅する小さな天文台'];
  static const _slotCount = 5;

  final _pageController = PageController();
  final _carouselGestureKey = GlobalKey();
  final List<IdeaSlotData?> _slotIdeas = List<IdeaSlotData?>.filled(
    _slotCount,
    null,
  );
  int _currentPage = 0;
  int? _activePointer;
  int? _pressedSlotIndex;
  Offset? _touchOrigin;
  bool _hasDragged = false;
  double _rotationX = 0;
  bool _isLoading = false;
  String? _loadError;

  bool get _isPreview => kDebugMode && _developmentPreview;
  int get _occupiedCount => _slotIdeas.whereType<IdeaSlotData>().length;

  @override
  void initState() {
    super.initState();
    if (_isPreview) {
      for (var index = 0; index < _previewTitles.length; index++) {
        _slotIdeas[index] = IdeaSlotData(
          ideaId: 'preview-idea-${index + 1}',
          title: _previewTitles[index],
          expiresAt: DateTime.now().add(Duration(days: 6 - index)),
          previewDescription: index == 0
              ? '青い花が咲く庭に、朝日が差し込む景色。'
              : '山の上を旅する、小さな天文台の物語。',
          previewTags: index == 0 ? const ['風景', 'ファンタジー'] : const ['星', '旅'],
        );
      }
    } else if (widget.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSlots());
    }
  }

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

  Future<String> _getIdToken() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('ログイン情報を取得できません。再度ログインしてください。');
    }
    return token;
  }

  String _messageFromResponse(http.Response response) {
    try {
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      final error = (payload as Map<String, dynamic>)['error'];
      if (error is Map<String, dynamic> && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {
      return '通信に失敗しました。時間をおいて再試行してください。';
    }
    return '通信に失敗しました。時間をおいて再試行してください。';
  }

  Future<void> _loadSlots({bool showLoading = true}) async {
    if (!widget.authenticated || _isPreview) return;
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final token = await _getIdToken();
      final response = await http
          .get(
            Uri.parse(
              '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/me/slots',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(_messageFromResponse(response));
      }
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final slots = payload['slots'] as Map<String, dynamic>;
      final ideas = List<IdeaSlotData?>.generate(_slotCount, (index) {
        final slot = slots['slot_$index'];
        if (slot is Map<String, dynamic>) {
          return IdeaSlotData(
            ideaId: slot['ideaId'] as String,
            title: slot['title'] as String? ?? '掲載中',
            expiresAt: DateTime.parse(slot['expiresAt'] as String),
          );
        }
        return null;
      });
      if (!mounted) return;
      setState(() {
        for (var index = 0; index < _slotCount; index++) {
          _slotIdeas[index] = ideas[index];
        }
        _loadError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error is StateError
              ? error.message.toString()
              : 'アイデア枠を読み込めませんでした。再試行してください。';
        });
      }
    } finally {
      if (showLoading && mounted) setState(() => _isLoading = false);
    }
  }

  void _openComposer(int slotIndex) {
    final ideaId = _newIdeaId();
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IdeaComposerScreen(
          onSubmit: (draft) => _submitIdea(slotIndex, ideaId, draft),
        ),
      ),
    );
  }

  void _openDetail(IdeaSlotData idea) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => IdeaDetailScreen(
          idea: idea,
          apiBaseUrl: widget.apiBaseUrl,
          authenticated: widget.authenticated,
          preview: _isPreview,
        ),
      ),
    );
  }

  Future<void> _submitIdea(
    int slotIndex,
    String ideaId,
    IdeaDraft draft,
  ) async {
    if (_isPreview) {
      if (!mounted) return;
      setState(() {
        _slotIdeas[slotIndex] = IdeaSlotData(
          ideaId: ideaId,
          title: draft.title,
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          previewDescription: draft.description,
          previewTags: draft.tags,
        );
      });
      return;
    }
    if (!widget.authenticated) {
      throw StateError('アイデアを投稿するにはログインしてください。');
    }

    final token = await _getIdToken();
    final response = await http
        .post(
          Uri.parse(
            '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/ideas',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'ideaId': ideaId,
            'title': draft.title,
            'description': draft.description,
            'tags': draft.tags,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(_messageFromResponse(response));
    }

    if (mounted) {
      setState(() {
        final firstEmptySlot = _slotIdeas.indexWhere((idea) => idea == null);
        if (firstEmptySlot >= 0) {
          _slotIdeas[firstEmptySlot] = IdeaSlotData(
            ideaId: ideaId,
            title: draft.title,
            expiresAt: DateTime.now().add(const Duration(days: 7)),
          );
        }
      });
      await _loadSlots(showLoading: false);
    }
  }

  String _newIdeaId() {
    final random = Random.secure();
    final bytes = List<int>.filled(16, 0);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    setState(() {
      _activePointer = event.pointer;
      _touchOrigin = event.localPosition;
      _pressedSlotIndex = _pageController.hasClients
          ? _pageController.page?.round() ?? _currentPage
          : _currentPage;
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
    final origin = _touchOrigin;
    final pressedSlotIndex = _pressedSlotIndex;
    final isTap =
        event is PointerUpEvent &&
        !_hasDragged &&
        origin != null &&
        (event.localPosition - origin).distance < 4;
    setState(() {
      _activePointer = null;
      _pressedSlotIndex = null;
      _touchOrigin = null;
      _hasDragged = false;
      _rotationX = 0;
    });
    if (isTap &&
        pressedSlotIndex != null &&
        pressedSlotIndex >= 0 &&
        pressedSlotIndex < _slotCount) {
      final idea = _slotIdeas[pressedSlotIndex];
      if (idea != null) {
        _openDetail(idea);
      } else if (!_isLoading) {
        _openComposer(pressedSlotIndex);
      }
    }
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
    final occupiedCount = _occupiedCount;

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
                  if (_isLoading) const LinearProgressIndicator(),
                  if (_loadError != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _loadError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _isLoading ? null : _loadSlots,
                          child: const Text('再試行'),
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
                          onPointerCancel: _onPointerEnd,
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
                                    final title = _slotIdeas[index]?.title;
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
