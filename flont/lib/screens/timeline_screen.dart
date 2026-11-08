import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/page_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../widgets/idea_card.dart';
import '../widgets/masonry_layout.dart';
import '../widgets/timeline_tag_bar.dart';
import 'idea_detail_screen.dart';
import '../theme/app_theme.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    this.apiBaseUrl = 'http://localhost:8080',
    this.authenticated = false,
    this.active = true,
    this.client,
    this.idTokenProvider,
  });

  final String apiBaseUrl;
  final bool authenticated;
  final bool active;
  // 通信と認証を差し替えて、API失敗後の再試行を実接続なしで検証できる。
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  // サンプルは明示的なデバッグプレビュー時だけ使用し、DBには保存しない。
  bool get _isPreview =>
      kDebugMode && const bool.fromEnvironment('DEV_PREVIEW');
  static const _sampleTitles = [
    '夜明けを待つ庭',
    '旅する小さな天文台',
    '雨の日だけ開く喫茶店',
    '雲の上で暮らす配達員',
    '月明かりと青い花',
    '海の底にある図書館',
  ];
  static const _sampleTags = [
    ['風景', 'ファンタジー'],
    ['星', '旅'],
    ['雨', '日常'],
    ['空', 'キャラクター'],
    ['月', '花'],
    ['海', '図書館'],
  ];
  static const _previewTags = [
    '風景',
    'ファンタジー',
    'キャラクター',
    '日常',
    '星',
    '旅',
    '雨',
    '空',
    '月',
    '花',
    '海',
    '図書館',
  ];
  String? _selectedTag;
  final _deletedPreviewIdeas = <String>{};
  List<Map<String, dynamic>> get _previewIdeas =>
      List.generate(
            30,
            (index) => <String, dynamic>{
              'ideaId': 'preview-idea-$index',
              'title':
                  '${_sampleTitles[index % _sampleTitles.length]} ${index + 1}',
              'tags': _sampleTags[index % _sampleTags.length],
              'createdAt': _sampleDate
                  .subtract(Duration(days: index))
                  .toIso8601String(),
              'description': 'このお題に合わせたイラストを描いてみてください。',
              'publishedUntil': _sampleDate
                  .add(const Duration(days: 7))
                  .toIso8601String(),
              'canPin': index % 5 != 0,
              'isOwn': index % 5 == 0,
              'hasDrawn': index % 5 == 1,
              'canSubmit': index % 5 > 1,
            },
          )
          .where(
            (idea) =>
                !_deletedPreviewIdeas.contains(idea['ideaId']) &&
                (_selectedTag == null ||
                    (idea['tags'] as List<String>).contains(_selectedTag)),
          )
          .toList();
  int get _previewPageCount => ((_previewIdeas.length + 9) ~/ 10).clamp(1, 3);

  void _selectTag(String? tag) {
    if (_selectedTag == tag) return;
    _selectedTag = tag;
    _loadPage(0);
  }

  late final http.Client _client = widget.client ?? http.Client();
  final _sampleDate = DateTime.now();
  final _scrollController = ScrollController();
  final List<String?> _cursors = [null];
  List<Map<String, dynamic>> _ideas = [];
  Set<String> _bookmarks = {};
  int _page = 0;
  int _retryPage = 0;
  bool _retryRefresh = false;
  String? _nextCursor;
  String? _error;
  int _loadGeneration = 0;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_isPreview || (widget.active && widget.authenticated)) _loadPage(0);
  }

  @override
  void didUpdateWidget(covariant TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _loadGeneration++;
      _loading = false;
    }
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.authenticated != widget.authenticated ||
        (!oldWidget.active && widget.active && !_isPreview)) {
      _loadGeneration++;
      _loading = false;
      _cursors.clear();
      _cursors.add(null);
      _ideas = [];
      _bookmarks = {};
      _page = 0;
      _nextCursor = null;
      _error = null;
      if (_isPreview || (widget.active && widget.authenticated)) _loadPage(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  // 認証済みトークンを付け、APIのエラーメッセージを画面へ伝える。
  Future<http.Response> _request(String path, {String method = 'GET'}) async {
    final token = widget.idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await widget.idTokenProvider!();
    if (token == null) throw StateError('再度ログインしてください。');
    final uri = Uri.parse(
      '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1$path',
    );
    final headers = {'Authorization': 'Bearer $token'};
    final response =
        await (method == 'POST'
                ? _client.post(uri, headers: headers)
                : method == 'DELETE'
                ? _client.delete(uri, headers: headers)
                : _client.get(uri, headers: headers))
            .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = '読み込みに失敗しました。再試行してください。';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        message = body['error']['message'] as String;
      } catch (_) {
        // JSON以外のエラー応答では共通メッセージを表示する。
      }
      throw StateError(message);
    }
    return response;
  }

  // サーバーのカーソルをページごとに保持し、10件ずつ前後に移動する。
  Future<void> _loadPage(int page, {bool refresh = false}) async {
    // 同じ一覧UIとページ切り替えを、通信なしの30件で確認できる。
    if (_isPreview) {
      final ideas = _previewIdeas;
      final targetPage = (refresh ? 0 : page).clamp(0, _previewPageCount - 1);
      setState(() {
        _page = targetPage;
        _error = null;
        _nextCursor = targetPage + 1 < _previewPageCount
            ? 'preview-page-'
            : null;
        _ideas = ideas.skip(targetPage * 10).take(10).toList();
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return;
    }
    if (_loading || _saving || !widget.authenticated || !widget.active) return;
    final generation = ++_loadGeneration;
    // 失敗時に表示中のページではなく、取得を試みたページを再試行する。
    _retryPage = page;
    _retryRefresh = refresh;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cursor = refresh ? null : _cursors[page];
      final query = Uri(
        queryParameters: {'limit': '10', 'cursor': ?cursor},
      ).query;
      final responses = await Future.wait([
        _request('/ideas?$query'),
        _request('/me/pins'),
      ]);
      final data =
          jsonDecode(utf8.decode(responses[0].bodyBytes))
              as Map<String, dynamic>;
      final pins =
          jsonDecode(utf8.decode(responses[1].bodyBytes))
              as Map<String, dynamic>;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _ideas = (data['items'] as List).cast<Map<String, dynamic>>();
        _bookmarks = (pins['items'] as List)
            .map((item) => item['ideaId'] as String)
            .toSet();
        _nextCursor = data['nextCursor'] as String?;
        _page = page;
        if (refresh) {
          _cursors.clear();
          _cursors.add(null);
        }
        if (_cursors.length > page + 1) {
          _cursors.removeRange(page + 1, _cursors.length);
        }
        if (_nextCursor != null) _cursors.add(_nextCursor);
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '通信に失敗しました。再試行してください。',
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  // 保存成功後だけ表示を切り替え、DBと画面の状態をそろえる。
  Future<void> _toggleBookmark(String id) async {
    // プレビューのブックマークは画面内だけで切り替える。
    if (_isPreview) {
      setState(() {
        if (!_bookmarks.add(id)) _bookmarks.remove(id);
      });
      return;
    }
    if (_saving || _loading) return;
    setState(() => _saving = true);
    try {
      final removing = _bookmarks.contains(id);
      await _request('/pins/$id', method: removing ? 'DELETE' : 'POST');
      if (!mounted) return;
      setState(() {
        if (removing) {
          _bookmarks.remove(id);
        } else {
          _bookmarks.add(id);
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'ブックマークを更新できませんでした。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // カードごとのIDを詳細へ渡し、APIから対応する本文を読み込む。
  Future<void> _openDetail(Map<String, dynamic> idea) async {
    final id = idea['ideaId'] as String;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => IdeaDetailScreen(
          idea: IdeaSlotData(
            ideaId: id,
            title: idea['title'] as String,
            expiresAt: DateTime.parse(idea['publishedUntil'] as String),
            createdAt: DateTime.parse(idea['createdAt'] as String),
            previewDescription: idea['description'] as String?,
            previewTags: (idea['tags'] as List).cast<String>(),
          ),
          apiBaseUrl: widget.apiBaseUrl,
          authenticated: widget.authenticated,
          preview: _isPreview,
          previewCanSubmit: idea['canSubmit'] == true,
          onDelete: idea['isOwn'] == true
              ? () async {
                  if (!_isPreview) {
                    await _request('/ideas/$id', method: 'DELETE');
                  }
                }
              : null,
        ),
      ),
    );
    if (!mounted || deleted != true) return;
    if (_isPreview) {
      _deletedPreviewIdeas.add(id);
      _loadPage(_page);
    } else {
      await _loadPage(0, refresh: true);
    }
  }

  Widget _buildIdeaCard(Map<String, dynamic> idea) {
    final id = idea['ideaId'] as String;
    final bookmarked = _bookmarks.contains(id);
    return IdeaCard(
      key: ValueKey(id),
      sketchStyle: true,
      statusLabel: idea['isOwn'] == true
          ? '自分のアイデア'
          : idea['hasDrawn'] == true
          ? '描いたアイデア'
          : null,
      onTap: () => _openDetail(idea),
      title: idea['title'] as String,
      borderColor: idea['isOwn'] == true
          ? AppColors.accentGreen
          : idea['hasDrawn'] == true
          ? AppColors.accentYellow
          : null,
      backgroundColor: idea['isOwn'] == true
          ? AppColors.ownIdea
          : idea['hasDrawn'] == true
          ? AppColors.drawnIdea
          : null,
      tags: (idea['tags'] as List).cast<String>(),
      date: DateTime.parse(idea['createdAt'] as String),
      pinned: bookmarked,
      onPinPressed:
          _loading || _saving || (!bookmarked && idea['canPin'] != true)
          ? null
          : () => _toggleBookmark(id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    if (!_isPreview && !widget.authenticated) {
      return const Center(child: Text('ログインするとお題を表示できます。'));
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.bodyWidth),
        child: Column(
          children: [
            if (_isPreview) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPadding,
                  8,
                  layout.horizontalPadding,
                  0,
                ),
                child: TimelineTagBar(
                  tags: _previewTags,
                  selectedTag: _selectedTag,
                  onSelected: _selectTag,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPadding,
                  4,
                  layout.horizontalPadding,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selectedTag == null ? 'すべて' : '#$_selectedTag'} / ${_previewIdeas.length}件',
                    key: const ValueKey('timeline-tag-summary'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => _loadPage(_retryPage, refresh: _retryRefresh),
                      child: const Text('再試行'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900
                      ? 3
                      : constraints.maxWidth >= 600
                      ? 2
                      : 1;

                  return ListView.separated(
                    controller: _scrollController,
                    padding: layout.insets,
                    itemCount: 2,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == 1) {
                        if (_page == 0 && _nextCursor == null) {
                          return !_loading && _error == null && _ideas.isEmpty
                              ? Center(
                                  child: Text(
                                    _selectedTag == null
                                        ? '掲載中のお題はありません。'
                                        : 'このタグのお題はありません。',
                                  ),
                                )
                              : const SizedBox.shrink();
                        }
                        // 前後ボタンの代わりに、取得可能なページを番号で選ぶ。
                        final pageCount = _isPreview
                            ? _previewPageCount
                            : _cursors.length;
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var page = 0; page < pageCount; page++)
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  backgroundColor: page == _page
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : null,
                                ),
                                onPressed: _loading || _saving || page == _page
                                    ? null
                                    : () => _loadPage(page),
                                child: Semantics(
                                  selected: page == _page,
                                  label: '${page + 1}ページ',
                                  child: Text('${page + 1}'),
                                ),
                              ),
                          ],
                        );
                      }
                      return MasonryLayout(
                        columns: columns,
                        children: _ideas.map(_buildIdeaCard).toList(),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
