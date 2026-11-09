import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/page_layout.dart';
import '../widgets/page_loading_gap.dart';
import '../widgets/profile_card.dart';
import 'profile_editor_screen.dart';
import 'idea_history_screen.dart';
import 'drawing_history_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.me,
    this.googleEmail,
    this.apiBaseUrl = 'http://localhost:8080',
    this.active = true,
    this.client,
    this.idTokenProvider,
  });

  // ログインしたユーザーの名前と実際の累計を表示する。
  final Map<String, dynamic>? me;
  final String? googleEmail;
  // 履歴にもログイン時と同じAPI接続先を引き継ぐ。
  final String apiBaseUrl;
  final bool active;
  // 通信と認証を差し替え、累計更新の失敗・再試行も検証する。
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  late final http.Client _client = widget.client ?? http.Client();
  late Map<String, dynamic>? _me = widget.me;
  bool _loading = false;
  bool _routeOpen = false;
  String? _error;
  int _generation = 0;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  bool get _previewMode => const bool.fromEnvironment('DEV_PREVIEW');

  bool get _canLoad =>
      mounted &&
      widget.active &&
      !_routeOpen &&
      _lifecycle == AppLifecycleState.resumed &&
      widget.me?['uid'] is String &&
      !_previewMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    if (_canLoad) _refresh();
  }

  void _invalidate() {
    // 画面離脱・ユーザー切替後の遅い応答は表示へ反映しない。
    _generation++;
    _loading = false;
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.me?['uid'] != widget.me?['uid'] ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl;
    if (identityChanged) {
      _invalidate();
      _me = widget.me;
      _error = null;
    }
    if (oldWidget.active && !widget.active) _invalidate();
    if (_canLoad && (identityChanged || !oldWidget.active)) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      if (_canLoad) _refresh();
    } else {
      setState(_invalidate);
    }
  }

  Future<void> _refresh() async {
    if (!_canLoad || _loading) return;
    final generation = ++_generation;
    final uid = widget.me!['uid'];
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = widget.idTokenProvider == null
          ? await FirebaseAuth.instance.currentUser?.getIdToken()
          : await widget.idTokenProvider!();
      if (!mounted || generation != _generation) return;
      if (token == null || token.isEmpty) throw StateError('再度ログインしてください。');
      final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
      final response = await _client
          .get(
            Uri.parse('$base/api/v1/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) return;
      if (response.statusCode != 200) {
        var message = '累計を更新できませんでした。再試行してください。';
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          message = body['error']['message'] as String;
        } catch (_) {
          // 不正なエラー応答でも直前のプロフィールを維持する。
        }
        throw StateError(message);
      }
      final me =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (me['uid'] != uid ||
          me['nickname'] is! String ||
          [
            'ideaCount',
            'drawnCount',
            'likesReceived',
          ].any((key) => me[key] is! int || (me[key] as int) < 0)) {
        throw StateError('累計を更新できませんでした。再試行してください。');
      }
      // 投稿・いいね等による増減は推測せず、サーバーの累計をそのまま採用する。
      setState(() => _me = me);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '累計を更新できませんでした。再試行してください。',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(Widget page) async {
    _routeOpen = true;
    setState(_invalidate);
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    _routeOpen = false;
    // 履歴内のお題削除後も、マイページへ戻れば最新の累計に置き換える。
    if (_canLoad) await _refresh();
  }

  Future<void> _openProfileEditor() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProfileEditorScreen(
          nickname: _me?['nickname'] as String? ?? '',
          bio: _me?['bio'] as String? ?? '',
          socialLinks: (_me?['socialLinks'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((link) => Map<String, dynamic>.from(link))
              .toList(growable: false),
          previewOnly: _previewMode,
          onSave: _saveProfile,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _me = result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_previewMode ? 'プレビューに反映しました' : 'プロフィールを保存しました')),
    );
  }

  Future<Map<String, dynamic>> _saveProfile(
    String nickname,
    String bio,
    List<Map<String, dynamic>> socialLinks,
  ) async {
    if (_previewMode) {
      return {
        ...?_me,
        'nickname': nickname,
        'bio': bio,
        'socialLinks': socialLinks,
      };
    }
    final token = widget.idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await widget.idTokenProvider!();
    if (token == null || token.isEmpty) throw StateError('再度ログインしてください。');
    final base = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client
        .patch(
          Uri.parse('$base/api/v1/me/profile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'nickname': nickname,
            'bio': bio,
            'socialLinks': socialLinks,
          }),
        )
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic> body;
    try {
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('サーバーからの応答を読み取れませんでした。もう一度お試しください。');
    }
    if (response.statusCode != 200) {
      final error = body['error'];
      final message = error is Map<String, dynamic>
          ? error['message'] as String? ?? 'プロフィールを保存できませんでした。'
          : 'プロフィールを保存できませんでした。';
      throw StateError(message);
    }
    if (body['uid'] != widget.me?['uid'] ||
        body['nickname'] != nickname ||
        body['bio'] != bio ||
        body['socialLinks'] is! List) {
      throw StateError('保存結果を確認できませんでした。再読み込みしてご確認ください。');
    }
    return body;
  }

  @override
  void dispose() {
    _invalidate();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    final profileCardWidth = layout.contentWidth < 320
        ? layout.contentWidth
        : 320.0;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.bodyWidth),
        child: ListView(
          padding: EdgeInsets.only(
            left: layout.horizontalPadding,
            right: layout.horizontalPadding,
            bottom: PageLayout.verticalGap,
          ),
          children: [
            PageLoadingGap(loading: _loading),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('マイページ', style: Theme.of(context).textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    _open(
                      SettingsScreen(
                        nickname: _me?['nickname'] as String?,
                        googleEmail: widget.googleEmail,
                        // 設定内のデモにも共通のAPI接続先を渡す。
                        apiBaseUrl: widget.apiBaseUrl,
                      ),
                    );
                  },
                ),
              ],
            ),

            if (_me != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('profile-edit'),
                  onPressed: _openProfileEditor,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('プロフィールを編集'),
                ),
              ),

            if (_error != null)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _canLoad && !_loading ? _refresh : null,
                    child: const Text('再試行'),
                  ),
                ],
              ),

            const SizedBox(height: PageLayout.verticalGap),

            _buildPublicProfilePreview(context),

            const SizedBox(height: PageLayout.verticalGap),

            // プロフィールカード
            Center(
              child: ProfileCard(
                width: profileCardWidth,
                nickname: _me?['nickname'] as String? ?? '未ログイン',
                ideaCount: _me?['ideaCount'] as int? ?? 0,
                drawingCount: _me?['drawnCount'] as int? ?? 0,
                likeCount: _me?['likesReceived'] as int? ?? 0,
              ),
            ),

            const SizedBox(height: PageLayout.verticalGap),

            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.threed_rotation, size: 18),
                SizedBox(width: 8),
                // 狭い画面や大きな文字設定でも説明を折り返す。
                Flexible(child: Text('カードをタップして裏返す')),
              ],
            ),

            const SizedBox(height: PageLayout.verticalGap),

            Text('創作の履歴', style: Theme.of(context).textTheme.titleMedium),

            const SizedBox(height: PageLayout.verticalGap),

            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: const Text('アイデア履歴'),
                    subtitle: const Text('投稿したお題を確認する'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _open(
                        IdeaHistoryScreen(
                          apiBaseUrl: widget.apiBaseUrl,
                          authenticated: widget.me != null,
                          client: widget.client,
                          idTokenProvider: widget.idTokenProvider,
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.brush_outlined),
                    title: const Text('描いた履歴'),
                    subtitle: const Text('参加したお題を振り返る'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _open(
                        DrawingHistoryScreen(
                          apiBaseUrl: widget.apiBaseUrl,
                          authenticated: widget.me != null,
                          client: widget.client,
                          idTokenProvider: widget.idTokenProvider,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicProfilePreview(BuildContext context) {
    final theme = Theme.of(context);
    final bio = _me?['bio'] as String? ?? '';
    final links = (_me?['socialLinks'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((link) => Map<String, dynamic>.from(link))
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('プロフィール', style: theme.textTheme.titleMedium),
                ),
                if (_previewMode)
                  Text('公開表示イメージ', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              bio.isEmpty ? '自己紹介はまだありません' : bio,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: bio.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
            if (links.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              for (final link in links)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_new, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              link['label'] as String? ?? 'SNSリンク',
                              style: theme.textTheme.labelLarge,
                            ),
                            Text(
                              link['url'] as String? ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ] else ...[
              const SizedBox(height: 8),
              Text('SNSリンクは未登録です', style: theme.textTheme.bodySmall),
            ],
            if (_previewMode) ...[
              const SizedBox(height: 12),
              Text(
                'ここに表示される内容はプレビュー用サンプルです。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
