import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../theme/page_layout.dart';
import '../models/artwork_image_format.dart';
import '../widgets/idea_card.dart';

/// 画像の選択から確認までを試すUI。アップロードやDBへの書き込みは行わない。
class ArtworkComposerScreen extends StatefulWidget {
  const ArtworkComposerScreen({
    super.key,
    required this.ideaId,
    required this.ideaTitle,
    required this.ideaCreatedAt,
    this.ideaTags = const [],
    this.pickImage,
  });

  final String ideaId;
  final String ideaTitle;
  final DateTime ideaCreatedAt;
  final List<String> ideaTags;
  // テストではファイルダイアログを差し替えて選択・キャンセルを検証する。
  final Future<XFile?> Function()? pickImage;

  @override
  State<ArtworkComposerScreen> createState() => _ArtworkComposerScreenState();
}

class _ArtworkComposerScreenState extends State<ArtworkComposerScreen> {
  Uint8List? _bytes;
  String? _filename;
  String? _error;
  bool _picking = false;
  bool _demoComplete = false;
  bool _confirming = false;
  bool _previewAvailable = false;
  int? _previewWidth;
  int? _previewHeight;
  ArtworkImageFormat? _format;

  String get _formatLabel => switch (_format) {
    ArtworkImageFormat.png => 'PNG',
    ArtworkImageFormat.jpeg => 'JPEG',
    ArtworkImageFormat.webp => 'WebP',
    ArtworkImageFormat.heif => 'HEIC/HEIF',
    null => '',
  };

  Future<XFile?> _openImage() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'イラスト',
        extensions: ['png', 'jpg', 'jpeg', 'webp', 'heic', 'heif'],
        mimeTypes: [
          'image/png',
          'image/jpeg',
          'image/webp',
          'image/heic',
          'image/heif',
        ],
        uniformTypeIdentifiers: [
          'public.png',
          'public.jpeg',
          'org.webmproject.webp',
          'public.heic',
          'public.heif',
        ],
      ),
    ],
  );

  Future<void> _selectImage() async {
    if (_picking || _confirming) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await (widget.pickImage ?? _openImage)();
      if (file == null || !mounted) return;
      checkArtworkImageSize(await file.length());
      final bytes = await file.readAsBytes();
      // Recheck the actual byte length, including files with inaccurate metadata.
      final format = checkArtworkImageFormat(file.name, bytes);
      var previewAvailable = false;
      var animated = false;
      int? previewWidth;
      int? previewHeight;
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        try {
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            final longest = descriptor.width > descriptor.height
                ? descriptor.width
                : descriptor.height;
            final scale = longest > 1600 ? 1600 / longest : 1.0;
            previewWidth = (descriptor.width * scale).round().clamp(1, 1600);
            previewHeight = (descriptor.height * scale).round().clamp(1, 1600);
            final codec = await descriptor.instantiateCodec(
              targetWidth: previewWidth,
              targetHeight: previewHeight,
            );
            try {
              if (codec.frameCount != 1) {
                animated = true;
                throw StateError('静止画を1枚選択してください。');
              }
              final frame = await codec.getNextFrame();
              frame.image.dispose();
              previewAvailable = true;
            } finally {
              codec.dispose();
            }
          } finally {
            descriptor.dispose();
          }
        } finally {
          buffer.dispose();
        }
      } catch (error) {
        // HEIF may need server conversion. Never pretend an unseen image was verified.
        if (animated || format != ArtworkImageFormat.heif) rethrow;
      }
      if (!mounted) return;
      _format = format;
      _previewAvailable = previewAvailable;
      _previewWidth = previewWidth;
      _previewHeight = previewHeight;
      setState(() {
        _bytes = bytes;
        _filename = file.name;
        _demoComplete = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _filename = null;
          _format = null;
          _previewAvailable = false;
          _error = error is StateError
              ? error.message.toString()
              : '画像を読み込めませんでした。別の画像を選ぶか再試行してください。';
        });
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _confirmDemo() async {
    if (_bytes == null || !_previewAvailable || _picking || _confirming) return;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('送信内容の確認（デモ）'),
        content: Text(
          '「${widget.ideaTitle}」への送信操作を試します。\n$_filename ($_formatLabel)\n\n実送信後は取り消し・差し替えはできません。\nこれはデモです。画像はアップロードされず、相手にも届きません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            key: const ValueKey('artwork-confirm-demo'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('デモを実行'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    // 仮の完了状態だけを表示し、送信履歴や受付状態は変更しない。
    setState(() => _demoComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    final theme = Theme.of(context);
    if (_demoComplete) {
      // 完了時は入力欄を隠し、中央のチェックとホームへ戻る操作に絞る。
      return Scaffold(
        // 完了画面も共通テーマのヘッダーを表示し、戻る操作はホームへ統一する。
        appBar: AppBar(
          title: const Text('送信完了'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: layout.insets,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: layout.contentWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      key: const ValueKey('artwork-complete-check'),
                      size: 88,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text('送信完了（デモ）', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    const Text(
                      'これはデモです。画像は送信・保存されていません。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      key: const ValueKey('artwork-return-home'),
                      // 詳細・送信画面を閉じ、アプリの最初の画面へ戻る。
                      onPressed: () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                      child: const Text('ホームに戻る'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(title: const Text('イラストを送る')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.bodyWidth),
            // 短い内容は画面の高さを使い、長文や拡大文字では縦スクロールする。
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.horizontalPadding,
                      vertical: compact ? 8 : layout.padding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'UIプレビュー・実際には送信されません',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 20),
                        Text('送信先のお題', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 8),
                        // 一覧と同じ共通カードで、送信先のタグと投稿日も確認できる。
                        IdeaCard(
                          key: const ValueKey('artwork-target-idea'),
                          title: widget.ideaTitle,
                          tags: widget.ideaTags,
                          date: widget.ideaCreatedAt,
                          showBookmark: false,
                        ),
                        SizedBox(height: compact ? 12 : 24),
                        ...[
                          // 選択前後で領域を固定し、画像全体を縦横比を保って表示する。
                          Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: AspectRatio(
                              // 追加領域だけを横長にし、画像は引き続きcontainで表示する。
                              aspectRatio: 16 / 9,
                              child: _bytes == null
                                  ? InkWell(
                                      key: const ValueKey('artwork-pick-area'),
                                      onTap: _picking ? null : _selectImage,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_photo_alternate_outlined,
                                            size: 48,
                                            color: theme.colorScheme.primary,
                                          ),
                                          SizedBox(height: compact ? 8 : 16),
                                          Text(
                                            _picking ? '画像を読み込み中…' : 'イラストを選択',
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'PNG・JPEG・WebP・HEIC/HEIF / 30MB以内',
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  : !_previewAvailable
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'このHEIC/HEIFはブラウザで表示できません。\n画像変換への対応後に確認・送信できます。\n今はPNG・JPEG・WebPを選び直してください。',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  : Image.memory(
                                      _bytes!,
                                      key: const ValueKey('artwork-preview'),
                                      fit: BoxFit.contain,
                                      cacheWidth: _previewWidth,
                                      cacheHeight: _previewHeight,
                                      gaplessPlayback: true,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Center(
                                                child: Text(
                                                  '画像を表示できません。選び直してください。',
                                                ),
                                              ),
                                    ),
                            ),
                          ),
                          if (_picking) const LinearProgressIndicator(),
                          if (_filename != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _filename!,
                                    key: const ValueKey('artwork-filename'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  key: const ValueKey('artwork-reselect'),
                                  onPressed: _picking ? null : _selectImage,
                                  icon: const Icon(Icons.image_outlined),
                                  label: const Text('選び直す'),
                                ),
                              ],
                            ),
                          ],
                          if (_filename != null)
                            Text(
                              '$_formatLabel / ${(_bytes!.length / (1024 * 1024)).toStringAsFixed(2)} MB',
                              style: theme.textTheme.bodySmall,
                            ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 8 : 20),
                          Text(
                            '自作の静止画を選択してください。生成AI画像は送信できません。',
                            style: theme.textTheme.bodyMedium,
                          ),
                          SizedBox(height: compact ? 8 : 16),
                          // 余った高さはここで受け、送信操作を画面下側へ配置する。
                          const Spacer(),
                          FilledButton.icon(
                            key: const ValueKey('artwork-send-demo'),
                            onPressed:
                                _bytes == null ||
                                    !_previewAvailable ||
                                    _picking ||
                                    _confirming
                                ? null
                                : _confirmDemo,
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('送信を試す（デモ）'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'HEIC/HEIFは表示できない環境があります。実送信は未対応です。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
