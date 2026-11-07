import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../theme/page_layout.dart';
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
  static const _maxBytes = 30 * 1024 * 1024;
  Uint8List? _bytes;
  String? _filename;
  String? _error;
  bool _picking = false;
  bool _demoComplete = false;

  Future<XFile?> _openImage() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'イラスト',
        extensions: ['png', 'jpg', 'jpeg'],
        mimeTypes: ['image/png', 'image/jpeg'],
        uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
      ),
    ],
  );

  Future<void> _selectImage() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await (widget.pickImage ?? _openImage)();
      if (file == null || !mounted) return;
      final extension = file.name.split('.').last.toLowerCase();
      if (!['png', 'jpg', 'jpeg'].contains(extension)) {
        throw StateError('PNG・JPEGの画像を選択してください。');
      }
      final length = await file.length();
      if (length == 0 || length > _maxBytes) {
        throw StateError('空でない30MB以内の画像を選択してください。');
      }
      final bytes = await file.readAsBytes();
      // 名前を変更したWebPなども受け付けず、実体と拡張子の一致を確認する。
      const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final isPng =
          bytes.length >= pngSignature.length &&
          List.generate(
            pngSignature.length,
            (i) => bytes[i] == pngSignature[i],
          ).every((matches) => matches);
      final isJpeg =
          bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
      if ((extension == 'png' && !isPng) || (extension != 'png' && !isJpeg)) {
        throw StateError('PNG・JPEGの画像を選択してください。');
      }
      // 拡張子だけで判定せず、プレビュー可能な画像か確認する。
      // 縮小デコードで大きな画像のプレビュー用メモリを抑える。
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1600,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _filename = file.name;
        _demoComplete = false;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '画像を読み込めませんでした。別の画像を選ぶか再試行してください。',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _confirmDemo() async {
    if (_bytes == null || _picking) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('送信内容の確認（デモ）'),
        content: Text(
          '「${widget.ideaTitle}」への送信操作を試します。\n画像はアップロードされず、相手にも届きません。',
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
    if (confirmed != true || !mounted) return;
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
                                          const Text('PNG・JPEG / 30MB以内'),
                                        ],
                                      ),
                                    )
                                  : Image.memory(
                                      _bytes!,
                                      key: const ValueKey('artwork-preview'),
                                      fit: BoxFit.contain,
                                      cacheWidth: 1600,
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
                            '送信するのは、自分で描いたイラストにしてください。',
                            style: theme.textTheme.bodyMedium,
                          ),
                          SizedBox(height: compact ? 8 : 16),
                          // 余った高さはここで受け、送信操作を画面下側へ配置する。
                          const Spacer(),
                          FilledButton.icon(
                            key: const ValueKey('artwork-send-demo'),
                            onPressed: _bytes == null || _picking
                                ? null
                                : _confirmDemo,
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('送信を試す（デモ）'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '対応形式はPNG・JPEGのみです。実際の送信は今後対応します。',
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
