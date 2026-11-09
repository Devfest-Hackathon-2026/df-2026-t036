import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/page_layout.dart';
import '../widgets/page_loading_gap.dart';
import '../theme/app_theme.dart';
import '../widgets/received_artwork_card.dart';
import '../widgets/artwork_opening_route.dart';
import 'package:flutter/gestures.dart';
import 'ideas_screen.dart';
import 'artwork_detail_screen.dart';
import '../models/received_artwork.dart';
import '../preview/artwork_preview.dart';
import '../services/artwork_image_cache.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.artworkTitles = const [],
    this.artworks = const [],
    this.apiBaseUrl = 'http://localhost:8080',
    this.authenticated = false,
    this.active = true,
    this.client,
    this.idTokenProvider,
    this.userId,
  });

  // 実データの接続時は受信作品のタイトルを渡せる。
  final List<String> artworkTitles;
  final List<ReceivedArtwork> artworks;
  final String apiBaseUrl;
  final bool authenticated;
  final bool active;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;
  final String? userId;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  late final http.Client _client = widget.client ?? http.Client();
  late final _imageCache = ArtworkImageCache(now: () => _now);
  List<ReceivedArtwork> _inbox = [];
  final _previewReadAt = <String, DateTime>{};
  final _previewLikes = <String>{};
  final _previewDeleted = <String>{};
  String? _nextCursor;
  String? _error;
  bool _loading = false;
  bool _retryAppend = false;
  bool _detailOpen = false;
  int _generation = 0;
  int _failures = 0;
  Duration? _retryAfter;
  Timer? _refreshTimer;
  Timer? _expiryTimer;
  Duration _clockOffset = Duration.zero;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  bool get _isPreview =>
      kDebugMode && const bool.fromEnvironment('DEV_PREVIEW');
  bool get _canFetch =>
      mounted &&
      widget.active &&
      widget.authenticated &&
      !_isPreview &&
      !_detailOpen &&
      _lifecycle == AppLifecycleState.resumed;
  DateTime get _now => DateTime.now().add(_clockOffset);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    if (_canFetch) _loadInbox();
  }

  void _pause() {
    _generation++;
    _loading = false;
    _refreshTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      if (_canFetch) _loadInbox();
    } else {
      _pause();
    }
  }

  void _resetPage() {
    _page = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) _controller.jumpToPage(0);
    });
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final dates =
        _inbox
            .map((item) => item.expiresAt!)
            .where((date) => date.isAfter(_now))
            .toList()
          ..sort();
    if (dates.isEmpty) return;
    _expiryTimer = Timer(
      dates.first.difference(_now) + const Duration(milliseconds: 1),
      () {
        if (!mounted) return;
        setState(() {
          _inbox.removeWhere((item) => !item.expiresAt!.isAfter(_now));
          _resetPage();
        });
        _retainCachedImages();
        _scheduleExpiry();
      },
    );
  }

  Future<void> _loadInbox({bool append = false}) async {
    if (!_canFetch || _loading || (append && _nextCursor == null)) return;
    final generation = ++_generation;
    _refreshTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _retryAppend = append;
      _retryAfter = null;
    });
    try {
      final token = widget.idTokenProvider == null
          ? await FirebaseAuth.instance.currentUser?.getIdToken()
          : await widget.idTokenProvider!();
      if (token == null || token.isEmpty) throw StateError('再度ログインしてください。');
      if (!mounted || generation != _generation) return;
      final uri =
          Uri.parse(
            '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/me/artworks/inbox',
          ).replace(
            queryParameters: {
              'limit': '20',
              if (append) 'cursor': _nextCursor!,
            },
          );
      final response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) return;
      if (response.statusCode != 200) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          _imageCache.clear();
        }
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        if (seconds != null && seconds > 0) {
          _retryAfter = Duration(seconds: seconds);
        }
        var message = '受信作品を読み込めませんでした。';
        try {
          final body =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          message =
              (body['error'] as Map<String, dynamic>)['message'] as String;
        } catch (_) {}
        throw StateError(message);
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = (body['items'] as List)
          .map((item) => ReceivedArtwork.fromJson(item as Map<String, dynamic>))
          .toList();
      final serverTime = DateTime.parse(body['serverTime'] as String);
      final nextCursor = body['nextCursor'] as String?;
      setState(() {
        _clockOffset = serverTime.difference(DateTime.now());
        final combined = append ? [..._inbox, ...items] : items;
        _inbox = {
          for (final item in combined)
            if (item.expiresAt!.isAfter(_now)) item.submissionId: item,
        }.values.toList();
        _nextCursor = nextCursor;
        _failures = 0;
        if (!append) _resetPage();
      });
      _retainCachedImages();
      _scheduleExpiry();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _failures++;
          _error = error is StateError
              ? error.message.toString()
              : '読み込みに失敗しました。';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        if (_canFetch) {
          final multiplier = 1 << _failures.clamp(0, 3);
          final backoff = Duration(seconds: 180 * multiplier);
          _refreshTimer = Timer(
            _retryAfter != null && _retryAfter! > backoff
                ? _retryAfter!
                : backoff,
            _loadInbox,
          );
        }
      }
    }
  }

  Future<DateTime> _markArtworkRead(ReceivedArtwork artwork) async {
    final id = artwork.submissionId!;
    if (_isPreview) {
      final readAt = _previewReadAt.putIfAbsent(id, () => _now);
      if (mounted) setState(() {});
      return readAt;
    }
    final token = widget.idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await widget.idTokenProvider!();
    if (token == null || token.isEmpty) {
      throw StateError('Missing authentication');
    }
    final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client
        .post(
          Uri.parse('$base/api/v1/artworks/${Uri.encodeComponent(id)}/read'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Unable to mark artwork read');
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (body['submissionId'] != id) throw StateError('Unexpected artwork');
    final readAt = DateTime.parse(body['readAt'] as String);
    if (mounted) {
      setState(() {
        _inbox = _inbox
            .map(
              (item) =>
                  item.submissionId == id ? item.withReadAt(readAt) : item,
            )
            .toList();
      });
    }
    return readAt;
  }

  Future<void> _likeArtwork(ReceivedArtwork artwork) async {
    final id = artwork.submissionId!;
    if (_isPreview) {
      setState(() => _previewLikes.add(id));
      return;
    }
    final token = widget.idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await widget.idTokenProvider!();
    if (token == null || token.isEmpty) {
      throw StateError('Missing authentication');
    }
    final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client
        .post(
          Uri.parse('$base/api/v1/artworks/${Uri.encodeComponent(id)}/like'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw StateError('Unable to like artwork');
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (body['submissionId'] != id || body['liked'] != true) {
      throw StateError('Unexpected like response');
    }
    if (mounted) {
      setState(() {
        _inbox = _inbox
            .map((item) => item.submissionId == id ? item.withLiked() : item)
            .toList();
      });
    }
  }

  Future<void> _deleteArtwork(ReceivedArtwork artwork) async {
    final id = artwork.submissionId!;
    if (_isPreview) {
      setState(() {
        _previewDeleted.add(id);
        _imageCache.remove(id);
        _resetPage();
      });
      return;
    }
    final token = widget.idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await widget.idTokenProvider!();
    if (token == null || token.isEmpty) {
      throw StateError('再度ログインしてください。');
    }
    final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client
        .delete(
          Uri.parse('$base/api/v1/artworks/${Uri.encodeComponent(id)}'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 204) {
      var message = '作品を削除できませんでした。';
      try {
        message = ((jsonDecode(utf8.decode(response.bodyBytes))
                    as Map<String, dynamic>)['error']
                as Map<String, dynamic>)['message']
            as String;
      } catch (_) {}
      throw StateError(message);
    }
    _imageCache.remove(id);
    if (mounted) {
      setState(() {
        _inbox.removeWhere((item) => item.submissionId == id);
        _resetPage();
      });
    }
  }

  void _retainCachedImages() {
    _imageCache.retain({
      for (final artwork in _artworks)
        if (artwork.submissionId != null) artwork.submissionId!,
    });
  }

  Future<Uint8List> _cachedArtworkImage(ReceivedArtwork artwork) {
    Future<Uint8List> load() => _isPreview
        ? createPreviewArtwork(
            int.tryParse(artwork.submissionId!.split('-').last) ?? 0,
          )
        : _loadArtworkImage(artwork);
    final id = artwork.submissionId;
    if (id == null) return load();
    return _imageCache.load(id, expiresAt: artwork.expiresAt, loader: load);
  }

  Future<Uint8List> _loadArtworkImage(ReceivedArtwork artwork) async {
    var active = true;
    try {
      // 認証取得から画像の受信までに制限を設ける。
      return await (() async {
        final token = widget.idTokenProvider == null
            ? await FirebaseAuth.instance.currentUser?.getIdToken()
            : await widget.idTokenProvider!();
        if (!mounted || !active) throw StateError('画像取得を中止しました。');
        if (token == null || token.isEmpty) throw StateError('再度ログインしてください。');
        final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
        final id = Uri.encodeComponent(artwork.submissionId!);
        final response = await _client.get(
          Uri.parse('$base/api/v1/artworks/$id/image'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          throw StateError('画像を読み込めませんでした。');
        }
        return response.bodyBytes;
      })().timeout(const Duration(seconds: 30));
    } finally {
      active = false;
    }
  }

  final _cardKeys = <int, GlobalKey>{};

  Future<void> _openArtwork(ReceivedArtwork artwork, int index) async {
    if (_detailOpen) return;
    final cardBox = _cardKeys[index]?.currentContext?.findRenderObject();
    final navigatorBox = Navigator.of(
      context,
    ).overlay?.context.findRenderObject();
    if (cardBox is! RenderBox || navigatorBox is! RenderBox) return;
    final sourceRect =
        navigatorBox.globalToLocal(cardBox.localToGlobal(Offset.zero)) &
        cardBox.size;
    _detailOpen = true;
    _pause();
    await Navigator.of(context).push<bool>(
      ArtworkOpeningRoute(
        sourceRect: sourceRect,
        title: artwork.title,
        label: '受信作品 ${index + 1}',
        isUnread: artwork.readAt == null,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        builder: (_) => ArtworkDetailScreen(
          artwork: artwork,
          now: () => _now,
          imageLoader: () => _cachedArtworkImage(artwork),
          onImageInvalid: () {
            if (artwork.submissionId != null) {
              _imageCache.remove(artwork.submissionId!);
            }
          },
          onLike: artwork.submissionId == null
              ? null
              : () => _likeArtwork(artwork),
          allowFileActions: _isPreview,
          onDelete: () => _deleteArtwork(artwork),
          onMarkRead: artwork.submissionId == null
              ? null
              : () => _markArtworkRead(artwork),
        ),
      ),
    );
    if (!mounted) return;
    _detailOpen = false;
    if (_canFetch) _loadInbox();
  }

  static const _viewportFraction = 0.72;
  var _controller = PageController(viewportFraction: _viewportFraction);
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

  Widget _fitCard(Widget child) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 240) return child;
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: 240, height: 320, child: child),
      );
    },
  );

  Widget _buildCarousel(List<String> titles) => LayoutBuilder(
    builder: (context, space) {
      final fraction = (space.maxHeight * 3 / 4 / space.maxWidth).clamp(
        0.01,
        _viewportFraction,
      );
      if ((_controller.viewportFraction - fraction).abs() > 0.0001) {
        final previous = _controller;
        _controller = PageController(
          initialPage: _page,
          viewportFraction: fraction,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
      return _buildCarouselPages(titles);
    },
  );

  Widget _buildCarouselPages(List<String> titles) {
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
              key: ObjectKey(_controller),
              clipBehavior: Clip.none,
              controller: _controller,
              physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
              itemCount: titles.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) {
                final weight = (1.0 - (page - index).abs()).clamp(0.0, 1.0);
                final offset = (page - index).clamp(-1.0, 1.0);
                return Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: TiltCard(
                        key: ValueKey('inbox-tilt-$index'),
                        rotationX: _rotationX * weight,
                        rotationY: -offset * 0.16,
                        isDragging: (_pointer != null || moving) && weight > 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          key: _cardKeys.putIfAbsent(index, () => GlobalKey()),
                          onTap: () => _openArtwork(_artworks[index], index),
                          child: _fitCard(
                            ReceivedArtworkCard(
                              label: '受信作品 ${index + 1}',
                              title: titles[index],
                              isUnread: _artworks[index].readAt == null,
                            ),
                          ),
                        ),
                      ),
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
  late final _previewReceivedAt = DateTime.now().subtract(
    const Duration(hours: 2),
  );

  List<ReceivedArtwork> get _artworks {
    if (kDebugMode && const bool.fromEnvironment('DEV_PREVIEW')) {
      const titles = ['夜明けを待つ庭', '旅する小さな天文台', '月明かりと青い花'];
      const descriptions = [
        '青い花が咲く庭に、朝日が差し込む景色。',
        '山の上を旅する、小さな天文台の物語。',
        '月明かりに照らされた青い花を描いてほしいです。',
      ];
      return List.generate(titles.length, (index) {
            final receivedAt = _previewReceivedAt.subtract(
              Duration(days: index),
            );
            return ReceivedArtwork(
              submissionId: 'preview-artwork-$index',
              readAt: _previewReadAt['preview-artwork-$index'],
              title: titles[index],
              description: descriptions[index],
              tags: const ['風景', 'ファンタジー'],
              artistNickname: '描き手 ${index + 1}',
              createdAt: receivedAt,
              expiresAt: receivedAt.add(const Duration(days: 7)),
              liked:
                  index == 1 ||
                  _previewLikes.contains('preview-artwork-$index'),
            );
          })
          .where((artwork) => !_previewDeleted.contains(artwork.submissionId))
          .toList();
    }
    if (widget.authenticated) return _inbox;
    if (widget.artworks.isNotEmpty) return widget.artworks;
    return widget.artworkTitles
        .map((title) => ReceivedArtwork(title: title))
        .toList();
  }

  List<String> get _titles =>
      _artworks.map((artwork) => artwork.title).toList();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _expiryTimer?.cancel();
    _imageCache.clear();
    if (widget.client == null) _client.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.authenticated != widget.authenticated ||
        oldWidget.userId != widget.userId) {
      _imageCache.clear();
      _pause();
      _expiryTimer?.cancel();
      _inbox = [];
      _nextCursor = null;
      _error = null;
      _clockOffset = Duration.zero;
      _resetPage();
      if (_canFetch) _loadInbox();
    } else if (oldWidget.active != widget.active) {
      _pause();
      if (_canFetch) _loadInbox();
    }
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
        // 下部操作は本文内に置き、固定せずカードと一緒にスクロールさせる。
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
          child: Center(
            child: ConstrainedBox(
              // 外側の余白も含めた全体幅を他の画面にそろえる。
              constraints: BoxConstraints(maxWidth: layout.contentWidth),
              child: SizedBox(
                height: constraints.maxHeight.clamp(240.0, double.infinity),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageLoadingGap(loading: _loading),
                    Text(
                      '受信箱',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (_error != null)
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_error!),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => _loadInbox(append: _retryAppend),
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    const SizedBox(height: PageLayout.verticalGap),
                    Expanded(
                      child: ClipRect(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: PageLayout.verticalGap,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: layout.contentWidth,
                              ),
                              // 空の受信箱はカードの情報欄を出さず、中央の案内だけを表示する。
                              child: titles.isEmpty
                                  ? Text(
                                      _loading
                                          ? '読み込み中…'
                                          : _error != null
                                          ? '受信作品を表示できません'
                                          : 'まだ作品は届いていません',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    )
                                  : _buildCarousel(titles),
                            ),
                          ),
                          // 一作品の場合は切り替え操作を表示しない。
                        ),
                      ),
                    ),
                    if (_nextCursor != null &&
                        widget.authenticated &&
                        !_isPreview)
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => _loadInbox(append: true),
                        child: const Text('さらに読み込む'),
                      ),
                    // 一枚でも切替操作と同じ高さを確保し、複数枚とカード寸法をそろえる。
                    if (titles.length == 1) const SizedBox(height: 48),
                    if (titles.length > 1) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filledTonal(
                            tooltip: '前の作品',
                            onPressed: _page == 0
                                ? null
                                : () => _move(_page - 1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              '${_page + 1} / ${titles.length}',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: '次の作品',
                            onPressed: _page == titles.length - 1
                                ? null
                                : () => _move(_page + 1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
