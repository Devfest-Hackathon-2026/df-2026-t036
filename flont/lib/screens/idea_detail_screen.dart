import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';

class IdeaSlotData {
  const IdeaSlotData({
    required this.ideaId,
    required this.title,
    required this.expiresAt,
    this.previewDescription,
    this.previewTags = const [],
  });

  final String ideaId;
  final String title;
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
    this.preview = false,
  });

  final IdeaSlotData idea;
  final String apiBaseUrl;
  final bool authenticated;
  final bool preview;

  @override
  State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  late String _title = widget.idea.title;
  String _description = '';
  List<String> _tags = const [];
  late DateTime _publishedUntil = widget.idea.expiresAt;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preview) {
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
      _error = null;
    });
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('ログイン情報を取得できません。再度ログインしてください。');
      }
      final response = await http
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
        _title = idea['title'] as String;
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('アイデア詳細')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
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
            ],
          ),
        ),
      ),
    );
  }
}
