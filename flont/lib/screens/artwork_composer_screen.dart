import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../services/vision_image_processing.dart';

import '../theme/page_layout.dart';
import '../models/artwork_image_format.dart';
import '../widgets/idea_card.dart';

/// 画像の選択・事前変換・確認後に、認証付き投稿APIで送信する。
class ArtworkComposerScreen extends StatefulWidget {
  const ArtworkComposerScreen({
    super.key,
    required this.ideaId,
    required this.ideaTitle,
    required this.ideaCreatedAt,
    this.ideaTags = const [],
    this.pickImage,
    this.apiBaseUrl = 'http://localhost:8080',
    this.preview = false,
    this.client,
    this.idTokenProvider,
  });

  // 詳細画面と同じ接続先・認証を引き継ぎ、プレビューでは送信しない。
  final String apiBaseUrl;
  final bool preview;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;
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
  bool _complete = false;
  bool _confirming = false;
  bool _sending = false;
  // 結果不明の再送では画像を固定し、サーバーの同一入力による重複防止を利用する。
  bool _retryPending = false;
  http.Client? _activeClient;
  int _sendGeneration = 0;
  bool _previewAvailable = false;
  bool _shareArtistProfile = false;
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
    if (_picking || _confirming || _sending || _retryPending) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await (widget.pickImage ?? _openImage)();
      if (file == null || !mounted) return;
      checkArtworkImageSize(await file.length());
      final bytes = await file.readAsBytes();
      // ファイルの申告容量だけでなく、読み込んだ実データの容量と形式も確認する。
      final format = checkArtworkImageFormat(file.name, bytes);
      var previewAvailable = false;
      int? previewWidth;
      int? previewHeight;
      var prepared = bytes;
      try {
        // Web未対応のImageDescriptor.width/heightを使わず、実フレームを確認する。
        final image = await decodeArtworkImage(bytes);
        try {
          if (!mounted) return;
          final longest = image.width > image.height
              ? image.width
              : image.height;
          final scale = longest > 1600 ? 1600 / longest : 1.0;
          previewWidth = (image.width * scale).round().clamp(1, 1600);
          previewHeight = (image.height * scale).round().clamp(1, 1600);
          // 変換は選択時に一度だけ行い、同じデータで再試行できるよう保持する。
          if (!widget.preview) prepared = await encodeVisionImage(image);
          previewAvailable = true;
        } finally {
          image.dispose();
        }
      } catch (error) {
        // 非対応HEIFは未確認のまま送信せず、静止画・画素数の違反は拒否する。
        if (error is StateError || format != ArtworkImageFormat.heif) rethrow;
      }
      if (!mounted) return;
      if (!widget.preview && prepared.length > 20 * 1024 * 1024) {
        throw StateError('変換後の画像が20MBを超えました。小さい画像を選んでください。');
      }
      _format = !widget.preview && previewAvailable
          ? ArtworkImageFormat.png
          : format;
      _previewAvailable = previewAvailable;
      _previewWidth = previewWidth;
      _previewHeight = previewHeight;
      setState(() {
        _bytes = prepared;
        _filename = !widget.preview && previewAvailable
            ? '${file.name.substring(0, file.name.lastIndexOf('.'))}.png'
            : file.name;
        _complete = false;
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

  Future<void> _confirmSubmission() async {
    if (_bytes == null ||
        !_previewAvailable ||
        _picking ||
        _confirming ||
        _sending) {
      return;
    }
    if (_retryPending) {
      await _send();
      return;
    }
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(widget.preview ? '送信内容の確認（デモ）' : '送信内容の確認'),
        content: Text(
          widget.preview
              ? '「${widget.ideaTitle}」への送信操作を試します。\n$_filename ($_formatLabel)\nこれはデモです。画像は送信されません。'
              : '「${widget.ideaTitle}」へ送信します。\n$_filename ($_formatLabel)\n\nプロフィール公開: ${_shareArtistProfile ? 'する' : 'しない'}\n送信後は取り消し・差し替えできません。画像の審査を通過すると投稿が確定します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            key: const ValueKey('artwork-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.preview ? 'デモを実行' : '送信する'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    if (widget.preview) {
      setState(() => _complete = true);
    } else {
      await _send();
    }
  }

  Future<void> _send() async {
    if (_sending || _bytes == null) return;
    setState(() {
      _sending = true;
      _error = null;
      _retryPending = true;
    });
    final generation = ++_sendGeneration;
    final client = widget.client ?? http.Client();
    _activeClient = client;
    try {
      // 認証待ちから本文受信まで、操作全体を制限する。
      final response = await (() async {
        final token = widget.idTokenProvider != null
            ? await widget.idTokenProvider!()
            : await FirebaseAuth.instance.currentUser?.getIdToken();
        if (!mounted || generation != _sendGeneration) {
          throw StateError('送信を中止しました。');
        }
        if (token == null || token.isEmpty) {
          _retryPending = false;
          throw StateError('再度ログインしてください。');
        }
        final request =
            http.MultipartRequest(
                'POST',
                Uri.parse(
                  '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/artworks',
                ),
              )
              ..headers['Authorization'] = 'Bearer $token'
              ..fields['ideaId'] = widget.ideaId
              ..fields['shareArtistProfile'] = '$_shareArtistProfile'
              ..files.add(
                http.MultipartFile.fromBytes(
                  'file',
                  _bytes!,
                  filename: _filename,
                ),
              );
        return await http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 90));
      if (!mounted) return;
      Map<String, dynamic> body = {};
      try {
        body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        /* 不正な応答では成功扱いにせず、同じ画像で再試行する。 */
      }
      if (response.statusCode != 200 && response.statusCode != 201) {
        final detail = body['error'];
        final error = detail is Map ? detail : const {};
        _retryPending =
            response.statusCode >= 500 || error['code'] == 'SUBMISSION_BUSY';
        throw StateError(
          error['message'] is String
              ? error['message'] as String
              : '送信できませんでした。',
        );
      }
      if (body['submissionId'] is! String ||
          (body['submissionId'] as String).isEmpty ||
          body['submittedAt'] is! String ||
          DateTime.tryParse(body['submittedAt'] as String) == null) {
        throw StateError('送信結果を確認できません。同じ画像で再試行してください。');
      }
      setState(() {
        _complete = true;
        _retryPending = false;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '送信結果を確認できません。同じ画像で再試行してください。',
        );
      }
    } finally {
      // タイムアウト後に認証が遅れて完了しても、送信を新たに開始させない。
      _sendGeneration++;
      if (widget.client == null) client.close();
      _activeClient = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    // 画面を閉じた後の通信・表示更新を残さない。
    _sendGeneration++;
    if (widget.client == null) _activeClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    final theme = Theme.of(context);
    if (_complete) {
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
                    Text(
                      widget.preview ? '送信完了（デモ）' : '送信完了',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.preview
                          ? 'これはデモです。画像は送信・保存されていません。'
                          : 'イラストを送信しました。描いた履歴から確認できます。',
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
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
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
                            widget.preview
                                ? 'UIプレビュー・実際には送信されません'
                                : '画像を選び、内容を確認して送信してください。',
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
                                        key: const ValueKey(
                                          'artwork-pick-area',
                                        ),
                                        onTap:
                                            _picking ||
                                                _sending ||
                                                _retryPending
                                            ? null
                                            : _selectImage,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons
                                                  .add_photo_alternate_outlined,
                                              size: 48,
                                              color: theme.colorScheme.primary,
                                            ),
                                            SizedBox(height: compact ? 8 : 16),
                                            Text(
                                              _picking
                                                  ? '画像を読み込み中…'
                                                  : 'イラストを選択',
                                              style:
                                                  theme.textTheme.titleMedium,
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
                                    onPressed:
                                        _picking || _sending || _retryPending
                                        ? null
                                        : _selectImage,
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
                            CheckboxListTile(
                              key: const ValueKey('share-artist-profile'),
                              value: _shareArtistProfile,
                              onChanged: _sending || _retryPending
                                  ? null
                                  : (value) => setState(
                                      () =>
                                          _shareArtistProfile = value ?? false,
                                    ),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('受信者にプロフィールを公開する'),
                              subtitle: compact
                                  ? null
                                  : const Text(
                                      'オンにするとユーザーネーム・自己紹介・SNSリンクを見られます。初期設定は非公開です。',
                                    ),
                            ),
                            SizedBox(height: compact ? 8 : 16),
                            // 余った高さはここで受け、送信操作を画面下側へ配置する。
                            const Spacer(),
                            FilledButton.icon(
                              key: const ValueKey('artwork-send'),
                              onPressed:
                                  _bytes == null ||
                                      !_previewAvailable ||
                                      _picking ||
                                      _confirming ||
                                      _sending
                                  ? null
                                  : _confirmSubmission,
                              icon: const Icon(Icons.send_outlined),
                              label: Text(
                                widget.preview
                                    ? '送信を試す（デモ）'
                                    : _sending
                                    ? '送信しています…'
                                    : _retryPending
                                    ? '同じ画像で再試行'
                                    : '送信する',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'HEIC/HEIFは表示できない環境があります。画像は審査後に送信されます。',
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
      ),
    );
  }
}
