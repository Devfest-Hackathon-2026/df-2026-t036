import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/authenticated_api.dart';
import '../theme/page_layout.dart';
import '../widgets/idea_card.dart';
import 'idea_detail_screen.dart';

enum HistoryKind { ideas, drawings }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.kind,
    this.apiBaseUrl = 'http://localhost:8080',
    this.authenticated = false,
    this.client,
    this.idTokenProvider,
  });
  final HistoryKind kind;
  final String apiBaseUrl;
  final bool authenticated;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late AuthenticatedApi _api = _makeApi();
  AuthenticatedApi _makeApi() => AuthenticatedApi(
    baseUrl: widget.apiBaseUrl,
    client: widget.client,
    idTokenProvider: widget.idTokenProvider,
  );
  bool get _drawing => widget.kind == HistoryKind.drawings;
  bool get _preview => kDebugMode && const bool.fromEnvironment('DEV_PREVIEW');
  List<Map<String, dynamic>> _items = [];
  final _previewDeleted = <String>{};
  String? _cursor;
  String? _error;
  bool _loading = false;
  bool _retryAppend = false;
  int _generation = 0;
  Duration _clockOffset = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _api.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.apiBaseUrl != oldWidget.apiBaseUrl ||
        widget.authenticated != oldWidget.authenticated ||
        widget.kind != oldWidget.kind) {
      _generation++;
      _api.dispose();
      _api = _makeApi();
      _items = [];
      _error = null;
      _clockOffset = Duration.zero;
      _cursor = null;
      _loading = false;
      _load();
    }
  }

  Map<String, dynamic> _sample(int index) {
    final created = DateTime.now().subtract(Duration(days: [2, 10, 35][index]));
    final idea = <String, dynamic>{
      'ideaId': 'history-preview-$index',
      'title': ['夜明けの庭', '旅する天文台', '青い花'][index],
      'description': '履歴から開いたお題のプレビューです。',
      'tags': ['風景'],
      'createdAt': created.toIso8601String(),
      'publishedUntil': created.add(const Duration(days: 7)).toIso8601String(),
      'acceptUntil': created.add(const Duration(days: 30)).toIso8601String(),
    };
    return _drawing
        ? {
            'submissionId': 'preview-submission-$index',
            'ideaId': idea['ideaId'],
            'submittedAt': created
                .add(const Duration(hours: 2))
                .toIso8601String(),
            'lastLiked': index == 0,
            'ideaAvailability': index == 2 ? 'unavailable' : 'available',
            'idea': index == 2 ? null : idea,
          }
        : idea;
  }

  Future<void> _load({bool append = false}) async {
    if (_loading || (append && _cursor == null)) return;
    if (_preview) {
      setState(() {
        _items = List.generate(
          3,
          _sample,
        ).where((item) => !_previewDeleted.contains(item['ideaId'])).toList();
        _error = null;
      });
      return;
    }
    if (!widget.authenticated) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _retryAppend = append;
    });
    try {
      final data = await _api.get(
        _drawing ? '/me/drawn-history' : '/me/ideas',
        query: {'limit': '20', if (append) 'cursor': _cursor!},
      );
      final items = (data['items'] as List)
          .map(
            (item) => item is Map<String, dynamic> ? item : <String, dynamic>{},
          )
          .toList();
      final cursor = data['nextCursor'] as String?;
      final serverTime = DateTime.parse(data['serverTime'] as String);
      if (!mounted || generation != _generation) return;
      setState(() {
        _clockOffset = serverTime.difference(DateTime.now());
        _items = append ? [..._items, ...items] : items;
        _cursor = cursor;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '履歴を読み込めませんでした。',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(Map<String, dynamic> idea) async {
    final id = idea['ideaId'] as String;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => IdeaDetailScreen(
          idea: IdeaSlotData(
            ideaId: id,
            title: idea['title'] as String,
            expiresAt: DateTime.parse(idea['publishedUntil'] as String),
            createdAt: DateTime.parse(idea['createdAt'] as String),
            previewDescription: idea['description'] as String?,
            previewTags: (idea['tags'] as List).cast<String>(),
          ),
          apiBaseUrl: widget.apiBaseUrl,
          client: widget.client,
          idTokenProvider: widget.idTokenProvider,
          authenticated: widget.authenticated,
          preview: _preview,
          onDelete: _drawing
              ? null
              : () async {
                  if (!_preview) {
                    await _api.delete('/ideas/${Uri.encodeComponent(id)}');
                  }
                  if (mounted) {
                    setState(() {
                      if (_preview) _previewDeleted.add(id);
                      _generation++;
                      _loading = false;
                      _items.removeWhere((item) => item['ideaId'] == id);
                    });
                  }
                },
        ),
      ),
    );
    if (mounted && deleted == true && !_preview) _load();
  }

  Widget _unavailable(String message, {DateTime? submittedAt, bool? liked}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (submittedAt != null) Text('送信日: ${_date(submittedAt)}'),
              if (liked != null) Text(liked ? 'いいね済み' : 'いいね未受信'),
            ],
          ),
        ),
      );
  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.year}/${local.month}/${local.day}';
  }

  Widget _card(Map<String, dynamic> item) {
    try {
      final submittedAt = _drawing
          ? DateTime.parse(item['submittedAt'] as String)
          : null;
      final liked = _drawing ? item['lastLiked'] as bool : null;
      if (_drawing &&
          (item['ideaAvailability'] != 'available' || item['idea'] == null)) {
        return _unavailable('参照できません', submittedAt: submittedAt, liked: liked);
      }
      final idea = _drawing ? item['idea'] as Map<String, dynamic> : item;
      final created = DateTime.parse(idea['createdAt'] as String);
      final published = DateTime.parse(idea['publishedUntil'] as String);
      final accept = DateTime.parse(idea['acceptUntil'] as String);
      final id = idea['ideaId'] as String;
      final tags = List<String>.from(idea['tags'] as List);
      if (idea['description'] is! String) {
        throw const FormatException('Invalid idea');
      }
      final now = DateTime.now().add(_clockOffset);
      final status = now.isBefore(published)
          ? '掲載中'
          : now.isBefore(accept)
          ? 'ピン受付中'
          : '受付終了';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _drawing
                ? '送信日: ${_date(submittedAt!)} / ${liked! ? 'いいね済み' : 'いいね未受信'}'
                : status,
          ),
          const SizedBox(height: 6),
          IdeaCard(
            key: ValueKey('history-$id'),
            title: idea['title'] as String,
            tags: tags,
            date: created,
            showBookmark: false,
            onTap: () => _open(idea),
          ),
        ],
      );
    } catch (_) {
      return _unavailable('この履歴を読み込めませんでした。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_drawing ? '描いた履歴' : 'アイデア履歴'),
        actions: [
          IconButton(
            tooltip: '履歴を更新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.bodyWidth),
          child: ListView(
            padding: layout.insets,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => _load(append: _retryAppend),
                      child: const Text('再試行'),
                    ),
                  ],
                ),
              if (!_preview && !widget.authenticated)
                const Text('ログインすると履歴を表示できます。')
              else if (!_loading && _error == null && _items.isEmpty)
                const Text('まだ履歴はありません'),
              for (final item in _items) ...[
                _card(item),
                const SizedBox(height: 16),
              ],
              if (_cursor != null)
                TextButton(
                  onPressed: _loading ? null : () => _load(append: true),
                  child: const Text('さらに読み込む'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
