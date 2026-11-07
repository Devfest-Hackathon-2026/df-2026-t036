import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';
import '../theme/page_layout.dart';
import '../widgets/idea_card.dart';
import 'idea_detail_screen.dart';

/// 二つの履歴画面で認証・ページング・再試行を共用する。
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.drawn,
    required this.apiBaseUrl,
    required this.authenticated,
    this.client,
    this.idTokenProvider,
  });

  final bool drawn;
  final String apiBaseUrl;
  final bool authenticated;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  List<Map<String, dynamic>> _items = [];
  String? _cursor;
  String? _error;
  bool _loading = false;
  bool _retryAppend = false;
  int _generation = 0;
  Duration _offset = Duration.zero;
  bool get _preview => kDebugMode && const bool.fromEnvironment('DEV_PREVIEW');
  DateTime get _now => DateTime.now().add(_offset);

  @override
  void initState() {
    super.initState();
    if (widget.authenticated && !_preview) _load();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.authenticated != widget.authenticated ||
        oldWidget.drawn != widget.drawn) {
      // 接続対象が変わった後に古い応答やカーソルを混ぜない。
      _generation++;
      _items = [];
      _cursor = null;
      _error = null;
      _loading = false;
      if (widget.authenticated && !_preview) _load();
    }
  }

  Future<http.Response> _request(String path, {bool delete = false}) async {
    final token = widget.idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await widget.idTokenProvider!();
    if (token == null || token.isEmpty) throw StateError('再度ログインしてください。');
    final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/v1$path');
    final headers = {'Authorization': 'Bearer $token'};
    final response =
        await (delete
                ? _client.delete(uri, headers: headers)
                : _client.get(uri, headers: headers))
            .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404) throw StateError('参照できません');
      var message = '読み込みに失敗しました。再試行してください。';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        message = body['error']['message'] as String;
      } catch (_) {
        // JSON以外の応答でも既存の一覧を維持して再試行を案内する。
      }
      throw StateError(message);
    }
    return response;
  }

  Future<void> _load({bool append = false}) async {
    if (!widget.authenticated ||
        _preview ||
        (append && (_loading || _cursor == null))) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _retryAppend = append;
    });
    try {
      final query = Uri(
        queryParameters: {'limit': '20', if (append) 'cursor': _cursor!},
      ).query;
      final path = widget.drawn ? '/me/drawn-history' : '/me/ideas';
      final response = await _request('$path?$query');
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      final offset = DateTime.parse(
        body['serverTime'] as String,
      ).difference(DateTime.now());
      if (!mounted || generation != _generation) return;
      setState(() {
        // 更新成功時だけ後続ページを捨て、重複レコードはIDでまとめる。
        final all = append ? [..._items, ...items] : items;
        _items = {
          for (final item in all)
            item[widget.drawn ? 'submissionId' : 'ideaId']: item,
        }.values.toList();
        _cursor = body['nextCursor'] as String?;
        _offset = offset;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '読み込みに失敗しました。再試行してください。',
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
    // 詳細表示中に完了した古い一覧取得が、削除後の結果を上書きしないようにする。
    _generation++;
    setState(() => _loading = false);
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IdeaDetailScreen(
          idea: IdeaSlotData(
            ideaId: id,
            title: idea['title'] as String,
            createdAt: DateTime.parse(idea['createdAt'] as String),
            expiresAt: DateTime.parse(idea['publishedUntil'] as String),
          ),
          apiBaseUrl: widget.apiBaseUrl,
          authenticated: widget.authenticated,
          client: _client,
          idTokenProvider: widget.idTokenProvider,
          onDelete: widget.drawn
              ? null
              : () async {
                  await _request(
                    '/ideas/${Uri.encodeComponent(id)}',
                    delete: true,
                  );
                },
        ),
      ),
    );
    if (!mounted) return;
    if (deleted == true) {
      // 削除成功を直ちに反映し、再取得失敗でも削除済みカードを戻さない。
      setState(() => _items.removeWhere((row) => row['ideaId'] == id));
    }
    await _load();
  }

  String _status(Map<String, dynamic> idea) {
    if (_now.isBefore(DateTime.parse(idea['publishedUntil'] as String))) {
      return '掲載中';
    }
    if (_now.isBefore(DateTime.parse(idea['acceptUntil'] as String))) {
      return 'ピン受付中';
    }
    return '受付終了';
  }

  String _date(String value) {
    final date = DateTime.parse(value).toLocal();
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  Widget _item(Map<String, dynamic> item) {
    final idea = widget.drawn ? item['idea'] as Map<String, dynamic>? : item;
    final available =
        idea != null &&
        (!widget.drawn || item['ideaAvailability'] == 'available');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available)
          IdeaCard(
            title: idea['title'] as String,
            date: DateTime.parse(idea['createdAt'] as String),
            tags: (idea['tags'] as List).cast<String>(),
            showBookmark: false,
            backgroundColor: widget.drawn
                ? AppColors.drawnIdea
                : AppColors.ownIdea,
            borderColor: widget.drawn
                ? AppColors.accentYellow
                : AppColors.accentGreen,
            onTap: () => _open(idea),
          )
        else
          const Card(
            child: Padding(padding: EdgeInsets.all(20), child: Text('参照できません')),
          ),
        const SizedBox(height: 8),
        if (widget.drawn)
          Text(
            '送信日：${_date(item['submittedAt'] as String)}　${item['lastLiked'] == true ? 'いいね済み' : 'いいね未受信'}',
          )
        else
          Text(_status(idea!)),
      ],
    );
  }

  @override
  void dispose() {
    _generation++;
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.drawn ? '描いた履歴' : 'アイデア履歴'),
        actions: [
          IconButton(
            tooltip: '履歴を更新',
            onPressed: !widget.authenticated || _preview ? null : () => _load(),
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
              if (!widget.authenticated)
                const Text('履歴を表示するにはログインしてください。')
              else if (_preview)
                const Text('プレビューでは履歴を取得しません。')
              else ...[
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => _load(append: _retryAppend),
                    child: const Text('再試行'),
                  ),
                ],
                if (!_loading && _error == null && _items.isEmpty)
                  Text(widget.drawn ? 'まだ描いた履歴はありません。' : 'まだアイデア履歴はありません。'),
                for (final item in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _item(item),
                  ),
                if (_cursor != null)
                  TextButton(
                    onPressed: _loading ? null : () => _load(append: true),
                    child: const Text('さらに読み込む'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
