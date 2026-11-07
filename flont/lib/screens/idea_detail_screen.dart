import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';
import '../theme/page_layout.dart';
import 'artwork_composer_screen.dart';

class IdeaSlotData {
  const IdeaSlotData({
    required this.ideaId,
    required this.title,
    required this.expiresAt,
    this.previewDescription,
    this.createdAt,
    this.previewTags = const [],
  });

  final String ideaId;
  final String title;
  // 一覧APIが返す実際の投稿日をカードへ渡す。
  final DateTime? createdAt;
  final DateTime expiresAt;
  final String? previewDescription;
  final List<String> previewTags;
}

class IdeaDetailScreen extends StatefulWidget {
  const IdeaDetailScreen({
    super.key,
    required this.idea,
    required this.apiBaseUrl,
    required this.authenticated,
    this.onDelete,
    this.preview = false,
    this.previewCanSubmit = false,
    this.client,
    this.idTokenProvider,
  });

  final IdeaSlotData idea;
  final String apiBaseUrl;
  final bool authenticated;
  // 自分のお題を開く場合だけ削除処理を受け取る。
  final Future<void> Function()? onDelete;
  final bool preview;
  // プレビューでも、未描画で受付可能なお題だけ送信ボタンを表示する。
  final bool previewCanSubmit;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  late String _title = widget.idea.title;
  // プレビューでは期限から補完し、実データではAPIの投稿日を引き継ぐ。
  late DateTime _createdAt =
      widget.idea.createdAt ??
      widget.idea.expiresAt.subtract(const Duration(days: 7));
  String _description = '';
  List<String> _tags = const [];
  late DateTime _publishedUntil = widget.idea.expiresAt;
  bool _loading = true;
  bool _deleting = false;
  bool _isOwn = false;
  bool _canSubmit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preview) {
      _canSubmit = widget.previewCanSubmit;
      _description = widget.idea.previewDescription ?? '';
      _tags = widget.idea.previewTags;
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadIdea());
    }
  }

  Future<void> _loadIdea() async {
    if (!widget.authenticated) {
      setState(() {
        _loading = false;
        _error = 'アイデアを表示するにはログインしてください。';
      });
      return;
    }

    setState(() {
      _loading = true;
      // 再取得中は古い送信可否を使わない。
      _canSubmit = false;
      _error = null;
    });
    try {
      final token = widget.idTokenProvider == null
          ? await FirebaseAuth.instance.currentUser?.getIdToken()
          : await widget.idTokenProvider!();
      if (token == null || token.isEmpty) {
        throw StateError('ログイン情報を取得できません。再度ログインしてください。');
      }
      final response = await _client
          .get(
            Uri.parse(
              '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}'
              '/api/v1/ideas/${widget.idea.ideaId}',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(_messageFromResponse(response));
      }
      final idea =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _isOwn = idea['isOwn'] == true;
        // 色ではなく、サーバーの所有者・履歴・受付条件で送信可否を決める。
        _canSubmit =
            idea['canSubmit'] == true && !_isOwn && idea['hasDrawn'] != true;
        _title = idea['title'] as String;
        _createdAt = DateTime.parse(idea['createdAt'] as String);
        _description = idea['description'] as String;
        _tags = (idea['tags'] as List<dynamic>).cast<String>();
        _publishedUntil = DateTime.parse(idea['publishedUntil'] as String);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError
              ? error.message.toString()
              : 'アイデアを読み込めませんでした。再試行してください。';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  String get _remainingTime {
    final remaining = _publishedUntil.difference(DateTime.now());
    if (remaining <= Duration.zero) return '掲載終了';
    if (remaining.inDays > 0) {
      final hours = remaining.inHours.remainder(24);
      return hours == 0
          ? '掲載終了まであと${remaining.inDays}日'
          : '掲載終了まであと${remaining.inDays}日$hours時間';
    }
    if (remaining.inHours > 0) return '掲載終了まであと${remaining.inHours}時間';
    return '掲載終了まであと${remaining.inMinutes}分';
  }

  Future<void> _confirmDelete() async {
    if (widget.onDelete == null || (!widget.preview && !_isOwn)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('アイデアを削除しますか？'),
        content: const Text(
          'タイムライン掲載と新規受付を停止し、ピンを無効にします。'
          'すでに届いた作品は送信から7日間保持されます。削除は取り消せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const ValueKey('idea-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = error is StateError
              ? error.message.toString()
              : 'アイデアを削除できませんでした。再試行してください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 一覧と同じ三段階の幅・余白を詳細画面にも適用する。
    final layout = PageLayout.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('アイデア詳細')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.bodyWidth),
          child: ListView(
            padding: layout.insets,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loading ? null : _loadIdea,
                    icon: const Icon(Icons.refresh),
                    label: const Text('再試行'),
                  ),
                ),
              ],
              Text(_title, style: textTheme.headlineSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Text(
                    _remainingTime,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _description.isEmpty && _loading ? '読み込み中…' : _description,
                    style: textTheme.bodyLarge?.copyWith(height: 1.7),
                  ),
                ),
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('タグ', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [for (final tag in _tags) Chip(label: Text(tag))],
                ),
              ],
              if (_canSubmit && !_loading && _error == null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('idea-send-artwork-button'),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('イラストを送る'),
                  // 選択したお題を引き継ぎ、送信UIの試作画面へ進む。
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (context) => ArtworkComposerScreen(
                        ideaId: widget.idea.ideaId,
                        ideaTitle: _title,
                        ideaCreatedAt: _createdAt,
                        ideaTags: _tags,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              if (widget.onDelete != null && (widget.preview || _isOwn))
                OutlinedButton.icon(
                  key: const ValueKey('idea-delete-button'),
                  onPressed: _deleting ? null : _confirmDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: _deleting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(_deleting ? '削除中…' : 'アイデアを削除'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
