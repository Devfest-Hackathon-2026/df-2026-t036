import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/page_layout.dart';
import 'package:http/http.dart' as http;

import 'idea_composer_screen.dart';
import 'idea_detail_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/idea_card.dart';

const _developmentPreview = bool.fromEnvironment('DEV_PREVIEW');

class IdeasScreen extends StatefulWidget {
  const IdeasScreen({
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
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  static const _previewTitles = ['夜明けを待つ庭', '旅する小さな天文台'];
  static const _slotCount = 5;

  final List<IdeaSlotData?> _slotIdeas = List<IdeaSlotData?>.filled(
    _slotCount,
    null,
  );
  final _slotErrors = List<String?>.filled(_slotCount, null);
  late final http.Client _client = widget.client ?? http.Client();

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  bool _showBookmarks = false;
  bool _bookmarksLoading = false;
  bool _previewBookmarksInitialized = false;
  String? _bookmarksError;
  List<Map<String, dynamic>> _bookmarks = [];
  final _removingBookmarks = <String>{};
  bool _isLoading = false;
  String? _loadError;

  bool get _isPreview => kDebugMode && _developmentPreview;

  @override
  void initState() {
    super.initState();
    if (_isPreview) {
      for (var index = 0; index < _previewTitles.length; index++) {
        _slotIdeas[index] = IdeaSlotData(
          ideaId: 'preview-idea-${index + 1}',
          title: _previewTitles[index],
          expiresAt: DateTime.now().add(Duration(days: 6 - index)),
          previewDescription: index == 0
              ? '青い花が咲く庭に、朝日が差し込む景色。'
              : '山の上を旅する、小さな天文台の物語。',
          previewTags: index == 0 ? const ['風景', 'ファンタジー'] : const ['星', '旅'],
        );
      }
    } else if (widget.active && widget.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSlots());
    }
  }

  @override
  void didUpdateWidget(covariant IdeasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 他タブの保存解除・投稿・削除を、画面に戻った際の再取得で反映する。
    if (!_isPreview &&
        widget.active &&
        widget.authenticated &&
        (!oldWidget.active ||
            oldWidget.authenticated != widget.authenticated ||
            oldWidget.apiBaseUrl != widget.apiBaseUrl)) {
      if (_showBookmarks) {
        _loadBookmarks();
      } else {
        _loadSlots();
      }
    }
  }

  // 切り替えのたびに保存済み一覧を取得し、TL側での変更も反映する。
  Future<void> _loadBookmarks() async {
    if (_bookmarksLoading) return;
    if (_isPreview) {
      // 再表示で初期化し直さず、プレビューで解除した状態を維持する。
      if (_previewBookmarksInitialized) return;
      _previewBookmarksInitialized = true;
      setState(() {
        _bookmarks = List.generate(
          2,
          (index) => <String, dynamic>{
            'ideaId': 'preview-bookmark-$index',
            'title': ['雨の日だけ開く喫茶店', '海の底にある図書館'][index],
            'description': 'ブックマークしたお題のプレビューです。',
            'canSubmit': true,
            'publishedUntil': DateTime.now()
                .add(const Duration(days: 5))
                .toIso8601String(),
            'tags': ['風景', 'ファンタジー'],
            'createdAt': DateTime.now()
                .subtract(Duration(days: index))
                .toIso8601String(),
          },
        );
      });
      return;
    }
    if (!widget.authenticated) return;
    setState(() {
      _bookmarksLoading = true;
      _bookmarksError = null;
    });
    try {
      final token = await _getIdToken();
      final response = await _client
          .get(
            Uri.parse(
              '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/me/pins',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(_messageFromResponse(response));
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (mounted) {
        setState(
          () =>
              _bookmarks = (data['items'] as List).cast<Map<String, dynamic>>(),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _bookmarksError = error is StateError
              ? error.message.toString()
              : 'ブックマークを読み込めませんでした。',
        );
      }
    } finally {
      if (mounted) setState(() => _bookmarksLoading = false);
    }
  }

  // 自分のお題の削除操作と区別し、保存だけを解除する。
  Future<void> _removeBookmark(String id) async {
    if (!_removingBookmarks.add(id)) return;
    setState(() {});
    try {
      if (!_isPreview) {
        final token = await _getIdToken();
        final response = await _client
            .delete(
              Uri.parse(
                '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/pins/$id',
              ),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 204) {
          throw StateError(_messageFromResponse(response));
        }
      }
      if (mounted) {
        setState(() => _bookmarks.removeWhere((idea) => idea['ideaId'] == id));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError ? error.message.toString() : '保存を解除できませんでした。',
            ),
          ),
        );
      }
    } finally {
      _removingBookmarks.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<String> _getIdToken() async {
    final token = widget.idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await widget.idTokenProvider!();
    if (token == null || token.isEmpty) {
      throw StateError('ログイン情報を取得できません。再度ログインしてください。');
    }
    return token;
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

  Future<void> _loadSlots({bool showLoading = true}) async {
    if (!widget.authenticated || _isPreview) return;
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final token = await _getIdToken();
      final response = await _client
          .get(
            Uri.parse(
              '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/me/slots',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(_messageFromResponse(response));
      }
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final slots = payload['slots'] as Map<String, dynamic>;
      // 掲載枠の詳細から、TLと同じタイトル・タグ・投稿日を表示する。
      final errors = List<String?>.filled(_slotCount, null);
      final ideas = await Future.wait(
        List.generate(_slotCount, (index) async {
          final slot = slots['slot_$index'];
          // 新しい空Mapと旧形式のnullをどちらも空き枠として表示する。
          if (slot is! Map<String, dynamic> || slot.isEmpty) return null;
          try {
            final detail = await _client
                .get(
                  Uri.parse(
                    '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/ideas/${slot['ideaId']}',
                  ),
                  headers: {'Authorization': 'Bearer $token'},
                )
                .timeout(const Duration(seconds: 30));
            if (detail.statusCode != 200) {
              throw StateError(
                detail.statusCode == 403 || detail.statusCode == 404
                    ? '参照できません'
                    : _messageFromResponse(detail),
              );
            }
            final data =
                jsonDecode(utf8.decode(detail.bodyBytes))
                    as Map<String, dynamic>;
            return IdeaSlotData(
              ideaId: data['ideaId'] as String,
              title: data['title'] as String,
              createdAt: DateTime.parse(data['createdAt'] as String),
              expiresAt: DateTime.parse(data['publishedUntil'] as String),
              previewTags: (data['tags'] as List).cast<String>(),
            );
          } catch (error) {
            errors[index] = error is StateError
                ? error.message.toString()
                : '読み込みに失敗しました。';
            return null;
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        for (var index = 0; index < _slotCount; index++) {
          _slotIdeas[index] = ideas[index];
          _slotErrors[index] = errors[index];
        }
        _loadError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error is StateError
              ? error.message.toString()
              : 'アイデア枠を読み込めませんでした。再試行してください。';
        });
      }
    } finally {
      if (showLoading && mounted) setState(() => _isLoading = false);
    }
  }

  void _openComposer(int slotIndex) {
    final ideaId = _newIdeaId();
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IdeaComposerScreen(
          onSubmit: (draft) => _submitIdea(slotIndex, ideaId, draft),
        ),
      ),
    );
  }

  void _openDetail(IdeaSlotData idea, int slotIndex) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => IdeaDetailScreen(
          idea: idea,
          apiBaseUrl: widget.apiBaseUrl,
          authenticated: widget.authenticated,
          onDelete: () => _deleteIdea(idea, slotIndex),
          preview: _isPreview,
        ),
      ),
    );
  }

  Future<void> _deleteIdea(IdeaSlotData idea, int slotIndex) async {
    if (_isPreview) {
      if (mounted) setState(() => _slotIdeas[slotIndex] = null);
      return;
    }
    if (!widget.authenticated) {
      throw StateError('アイデアを削除するにはログインしてください。');
    }

    final token = await _getIdToken();
    final response = await _client
        .delete(
          Uri.parse(
            '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}'
            '/api/v1/ideas/${idea.ideaId}',
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 204) {
      throw StateError(_messageFromResponse(response));
    }

    if (mounted) {
      setState(() => _slotIdeas[slotIndex] = null);
      await _loadSlots(showLoading: false);
    }
  }

  Future<void> _submitIdea(
    int slotIndex,
    String ideaId,
    IdeaDraft draft,
  ) async {
    if (_isPreview) {
      if (!mounted) return;
      setState(() {
        _slotIdeas[slotIndex] = IdeaSlotData(
          ideaId: ideaId,
          title: draft.title,
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          previewDescription: draft.description,
          previewTags: draft.tags,
        );
      });
      return;
    }
    if (!widget.authenticated) {
      throw StateError('アイデアを投稿するにはログインしてください。');
    }

    final token = await _getIdToken();
    final response = await _client
        .post(
          Uri.parse(
            '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/ideas',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'ideaId': ideaId,
            'title': draft.title,
            'description': draft.description,
            'tags': draft.tags,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(_messageFromResponse(response));
    }

    if (mounted) {
      setState(() {
        final firstEmptySlot = _slotIdeas.indexWhere((idea) => idea == null);
        if (firstEmptySlot >= 0) {
          _slotIdeas[firstEmptySlot] = IdeaSlotData(
            ideaId: ideaId,
            title: draft.title,
            expiresAt: DateTime.now().add(const Duration(days: 7)),
          );
        }
      });
      await _loadSlots(showLoading: false);
    }
  }

  String _newIdeaId() {
    final random = Random.secure();
    final bytes = List<int>.filled(16, 0);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    // TLと同じ縦一列の一覧にし、空き枠を含む五つのスロットを表示する。
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.bodyWidth),
        child: ListView(
          padding: layout.insets,
          children: [
            Text(
              _showBookmarks ? '保存したアイデア' : 'アイデアノート',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              _showBookmarks
                  ? 'タイムラインのしおりから、5件まで保存できます。'
                  : '空き枠から、新しいアイデアを投稿できます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 360,
                child: SegmentedButton<bool>(
                  expandedInsets: EdgeInsets.zero,
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    minimumSize: WidgetStateProperty.all(const Size(56, 48)),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                    iconSize: WidgetStateProperty.all(20),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      tooltip: '自分のアイデア',
                      label: const Text('自分の投稿', maxLines: 1, softWrap: false),
                      icon: Icon(
                        _showBookmarks
                            ? Icons.lightbulb_outline
                            : Icons.lightbulb,
                      ),
                    ),
                    ButtonSegment(
                      value: true,
                      tooltip: 'ブックマーク',
                      label: const Text('保存済み', maxLines: 1, softWrap: false),
                      icon: Icon(
                        _showBookmarks ? Icons.bookmark : Icons.bookmark_border,
                      ),
                    ),
                  ],
                  selected: {_showBookmarks},
                  onSelectionChanged: (selection) {
                    setState(() => _showBookmarks = selection.single);
                    if (_showBookmarks) _loadBookmarks();
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_showBookmarks) ...[
              if (_bookmarksLoading) const LinearProgressIndicator(),
              if (_bookmarksError != null) ...[
                Text(_bookmarksError!),
                TextButton(onPressed: _loadBookmarks, child: const Text('再試行')),
              ],
              // 保存済みと空き枠を合わせ、常に五つのスロットを並べる。
              for (var index = 0; index < _slotCount; index++) ...[
                _buildBookmarkSlot(index),
                if (index < _slotCount - 1) const SizedBox(height: 12),
              ],
            ] else ...[
              if (_isLoading) const LinearProgressIndicator(),
              if (_loadError != null) ...[
                Text(_loadError!),
                TextButton(
                  onPressed: _isLoading ? null : _loadSlots,
                  child: const Text('再試行'),
                ),
              ],
              for (var index = 0; index < _slotCount; index++) ...[
                _buildSlot(index),
                if (index < _slotCount - 1) const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarkSlot(int index) {
    if (index < _bookmarks.length) {
      final idea = _bookmarks[index];
      return IdeaCard(
        key: ValueKey('bookmark-slot-${index + 1}'),
        sketchStyle: true,
        statusLabel: idea['hasDrawn'] == true ? '描いたアイデア' : '保存済み',
        title: idea['title'] as String,
        // 他の人のお題は閲覧用詳細を開き、削除操作を渡さない。
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (context) => IdeaDetailScreen(
              idea: IdeaSlotData(
                ideaId: idea['ideaId'] as String,
                title: idea['title'] as String,
                expiresAt: DateTime.parse(idea['publishedUntil'] as String),
                previewDescription: idea['description'] as String?,
                previewTags: (idea['tags'] as List).cast<String>(),
              ),
              apiBaseUrl: widget.apiBaseUrl,
              authenticated: widget.authenticated,
              preview: _isPreview,
              previewCanSubmit: idea['canSubmit'] == true,
            ),
          ),
        ),
        backgroundColor: idea['hasDrawn'] == true ? AppColors.drawnIdea : null,
        borderColor: idea['hasDrawn'] == true ? AppColors.accentYellow : null,
        tags: (idea['tags'] as List).cast<String>(),
        date: DateTime.parse(idea['createdAt'] as String),
        pinned: true,
        onPinPressed: _removingBookmarks.contains(idea['ideaId'])
            ? null
            : () => _removeBookmark(idea['ideaId'] as String),
      );
    }
    return _EmptyIdeaSlot(
      key: ValueKey('bookmark-slot-${index + 1}'),
      index: index,
      bookmark: true,
    );
  }

  Widget _buildSlot(int index) {
    // Keep unavailable occupied slots distinct from empty slots.
    if (_slotErrors[index] != null) {
      return Card(
        key: ValueKey('idea-slot-${index + 1}'),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_slotErrors[index]!),
              TextButton(
                onPressed: _isLoading ? null : _loadSlots,
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    }
    final idea = _slotIdeas[index];
    if (idea != null) {
      return IdeaCard(
        key: ValueKey('idea-slot-${index + 1}'),
        sketchStyle: true,
        statusLabel: '掲載中',
        title: idea.title,
        backgroundColor: AppColors.ownIdea,
        borderColor: AppColors.accentGreen,
        tags: idea.previewTags,
        date:
            idea.createdAt ?? idea.expiresAt.subtract(const Duration(days: 7)),
        showBookmark: false,
        onTap: () => _openDetail(idea, index),
      );
    }
    return _EmptyIdeaSlot(
      key: ValueKey('idea-slot-${index + 1}'),
      index: index,
      bookmark: false,
      onTap: _isLoading || _loadError != null
          ? null
          : () => _openComposer(index),
    );
  }
}

/// Empty paper slots distinguish creating a post from saving someone else's idea.
class _EmptyIdeaSlot extends StatelessWidget {
  const _EmptyIdeaSlot({
    super.key,
    required this.index,
    required this.bookmark,
    this.onTap,
  });
  final int index;
  final bool bookmark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        label: bookmark ? 'ブックマークの空き枠 ${index + 1}' : '枠 ${index + 1}にアイデアを投稿',
        button: !bookmark,
        enabled: bookmark ? null : onTap != null,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: bookmark
                          ? AppColors.background
                          : Color.lerp(AppColors.surface, AppColors.main, 0.40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      bookmark
                          ? Icons.bookmark_border_rounded
                          : Icons.add_circle_outline,
                      size: bookmark ? 24 : 30,
                      color: bookmark ? AppColors.muted : AppColors.sub,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bookmark ? '保存枠 ${index + 1}' : 'アイデアを追加',
                          style: text.titleMedium?.copyWith(
                            color: bookmark ? AppColors.muted : AppColors.sub,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bookmark ? 'まだ保存されていません' : '空き枠 ${index + 1} / 5',
                          style: text.bodySmall,
                        ),
                      ],
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

/// アイデア枠と受信箱で共用する、操作中の傾きと復帰モーション。
class TiltCard extends StatelessWidget {
  const TiltCard({
    super.key,
    required this.child,
    required this.rotationX,
    required this.rotationY,
    required this.isDragging,
  });

  final Widget child;
  final double rotationX;
  final double rotationY;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    // 行列の補間を避け、角度を補間して毎フレーム有限の行列を作る。
    final target = Offset(
      rotationX.isFinite ? rotationX : 0,
      rotationY.isFinite ? rotationY : 0,
    );
    return TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(begin: Offset.zero, end: target),
      duration: isDragging ? Duration.zero : const Duration(milliseconds: 440),
      curve: isDragging ? Curves.linear : Curves.easeOutBack,
      child: child,
      builder: (context, angle, child) {
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.003)
          ..rotateX(angle.dx)
          ..rotateY(angle.dy);
        return Transform(
          key: key == null
              ? null
              : ValueKey('${(key as ValueKey).value}-transform'),
          transform: transform,
          alignment: Alignment.center,
          // 見た目だけ傾け、ポインターの座標変換へ透視行列を渡さない。
          transformHitTests: false,
          child: child,
        );
      },
    );
  }
}

class IdeaSlotCard extends StatelessWidget {
  const IdeaSlotCard({
    super.key,
    required this.slotNumber,
    this.title,
    this.label,
    this.subtitle = 'TL掲載中',
    this.emptyText = '空き枠',
    this.icon = Icons.lightbulb_outline,
    this.emptyIcon = Icons.add,
  });

  // 受信箱と見た目を共有し、画面ごとの文言とアイコンだけ変更する。
  final String? label;
  final String subtitle;
  final String emptyText;
  final IconData icon;
  final IconData emptyIcon;

  final int slotNumber;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isOccupied = title != null;

    // 外側の比率指定をそのままカードの輪郭に反映する。
    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isOccupied
                      ? colors.primaryContainer
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    isOccupied ? icon : emptyIcon,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ?? '枠 $slotNumber',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title ?? emptyText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isOccupied) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
