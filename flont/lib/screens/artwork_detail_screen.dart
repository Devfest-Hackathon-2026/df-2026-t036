import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/received_artwork.dart';
import '../theme/page_layout.dart';
import '../widgets/artwork_actions.dart';
import '../services/artwork_file_actions.dart';

class ArtworkDetailScreen extends StatefulWidget {
  const ArtworkDetailScreen({
    super.key,
    required this.artwork,
    this.imageLoader,
    this.onMarkRead,
    this.now,
    this.onLike,
    this.allowFileActions = false,
    this.onSave,
  });

  final ReceivedArtwork artwork;
  final Future<Uint8List> Function()? imageLoader;
  final Future<DateTime> Function()? onMarkRead;
  final DateTime Function()? now;
  final Future<void> Function()? onLike;
  final bool allowFileActions;
  final Future<void> Function(Uint8List bytes)? onSave;

  @override
  State<ArtworkDetailScreen> createState() => _ArtworkDetailScreenState();
}

class _ArtworkDetailScreenState extends State<ArtworkDetailScreen>
    with WidgetsBindingObserver {
  ReceivedArtwork get artwork => widget.artwork;
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  Uint8List? _bytes;
  bool _loadingImage = false;
  bool _imageVisible = false;
  bool _reading = false;
  bool _acting = false;
  late bool _liked = artwork.liked == true;
  String? _actionError;
  bool get _canAct => !_expired && _imageVisible && _bytes != null && !_acting;

  bool _expired = false;
  String? _imageError;
  String? _readError;
  late DateTime? _readAt = artwork.readAt;
  Timer? _expiryTimer;
  int _imageGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchExpiry();
    if (!_expired) _loadImage();
  }

  void _watchExpiry() {
    _expiryTimer?.cancel();
    final expiry = artwork.expiresAt;
    if (expiry == null) return;
    final remaining = expiry.difference(_now);
    if (remaining <= Duration.zero) {
      _expired = true;
      _imageGeneration++;
      _bytes = null;
      _loadingImage = false;
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(_watchExpiry);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(_watchExpiry);
  }

  @override
  void dispose() {
    _imageGeneration++;
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadImage() async {
    if (_expired || widget.imageLoader == null) return;
    final generation = ++_imageGeneration;
    setState(() {
      _loadingImage = true;
      _bytes = null;
      _imageVisible = false;
      _imageError = null;
    });
    try {
      final bytes = await widget.imageLoader!().timeout(
        const Duration(seconds: 30),
      );
      if (!mounted || generation != _imageGeneration || _expired) return;
      setState(() {
        _bytes = bytes;
        _loadingImage = false;
      });
    } catch (_) {
      if (!mounted || generation != _imageGeneration || _expired) return;
      setState(() {
        _loadingImage = false;
        _imageError = '画像の読み込みに失敗しました。';
      });
    }
  }

  Future<void> _markRead() async {
    if (_expired ||
        !_imageVisible ||
        _reading ||
        _readAt != null ||
        widget.onMarkRead == null) {
      return;
    }
    setState(() {
      _reading = true;
      _readError = null;
    });
    try {
      final readAt = await widget.onMarkRead!();
      if (!mounted || _expired) return;
      setState(() => _readAt = readAt);
    } catch (_) {
      if (!mounted || _expired) return;
      setState(() => _readError = '既読を記録できませんでした。');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _like() async {
    if (!_canAct || _liked || widget.onLike == null) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      await widget.onLike!();
      if (mounted && !_expired) setState(() => _liked = true);
    } catch (_) {
      if (mounted) setState(() => _actionError = 'いいねを送れませんでした。再度お試しください。');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _saveImage() async {
    if (!_canAct || !widget.allowFileActions) return;
    final bytes = _bytes!;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      if (widget.onSave != null) {
        await widget.onSave!(bytes);
      } else {
        await saveArtworkFile(bytes, 'artwork.png');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('画像の保存を開始しました')));
      }
    } catch (_) {
      if (mounted) setState(() => _actionError = '画像を保存できませんでした。');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Widget _image() {
    Widget content;
    if (_expired) {
      content = const Center(child: Text('閲覧期限切れ'));
    } else if (widget.imageLoader == null) {
      content = const Center(child: Text('画像表示は準備中です'));
    } else if (_loadingImage) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_imageError != null || _bytes == null) {
      content = _imageFailure();
    } else {
      content = Image.memory(
        _bytes!,
        fit: BoxFit.contain,
        semanticLabel: artwork.title,
        frameBuilder: (context, child, frame, synchronouslyLoaded) {
          if (frame != null && !_imageVisible) {
            _imageVisible = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_expired) {
                setState(() {});
                _markRead();
              }
            });
          }
          return frame == null
              ? const Center(child: CircularProgressIndicator())
              : child;
        },
        errorBuilder: (context, error, stackTrace) => _imageFailure(),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(aspectRatio: 3 / 4, child: content),
        ),
      ),
    );
  }

  Widget _imageFailure() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('画像の読み込みに失敗しました。'),
        TextButton(onPressed: _loadImage, child: const Text('画像を再試行')),
      ],
    ),
  );

  String _date(DateTime? value) {
    if (value == null) return '未取得';
    final date = value.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}/${pad(date.month)}/${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
  }

  String get _remaining {
    final expiresAt = artwork.expiresAt;
    if (expiresAt == null) return '未取得';
    final remaining = expiresAt.difference(_now);
    if (remaining <= Duration.zero) return '閲覧期限切れ';
    if (remaining.inDays > 0) {
      return 'あと${remaining.inDays}日${remaining.inHours.remainder(24)}時間';
    }
    if (remaining.inHours > 0) return 'あと${remaining.inHours}時間';
    return 'あと${remaining.inMinutes}分';
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('受信作品詳細')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.bodyWidth),
          child: ListView(
            padding: layout.insets,
            children: [
              Text(artwork.title, style: textTheme.headlineSmall),
              const SizedBox(height: 16),
              ArtworkActions(
                liked: _liked,
                onLike: _canAct && !_liked && widget.onLike != null
                    ? _like
                    : null,
                onSave: _canAct && widget.allowFileActions ? _saveImage : null,
                child: _image(),
              ),
              const SizedBox(height: 8),
              const Text('いいねは取り消せません。', textAlign: TextAlign.center),
              if (_acting) const LinearProgressIndicator(),
              if (_actionError != null)
                Text(
                  _actionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_readError != null && !_expired)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_readError!),
                    TextButton(
                      onPressed: _reading ? null : _markRead,
                      child: const Text('既読を再試行'),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('作品情報', style: textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _info(context, '作者', artwork.artistNickname ?? '未取得'),
                      _info(context, '受信日時', _date(artwork.createdAt)),
                      _info(context, '閲覧期限', _date(artwork.expiresAt)),
                      _info(context, '残り時間', _remaining),
                      _info(context, '閲覧状態', _readAt == null ? '未読' : '既読'),
                      _info(
                        context,
                        'いいね',
                        artwork.liked == null && !_liked
                            ? '未取得'
                            : _liked
                            ? 'いいね済み'
                            : '未送信',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('元のお題', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                artwork.description ?? 'お題の説明は未取得です。',
                style: textTheme.bodyLarge?.copyWith(height: 1.7),
              ),
              if (artwork.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final tag in artwork.tags) Chip(label: Text(tag)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
