import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/page_layout.dart';
import '../widgets/profile_card.dart';
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

  bool get _canLoad =>
      mounted &&
      widget.active &&
      !_routeOpen &&
      _lifecycle == AppLifecycleState.resumed &&
      widget.me?['uid'] is String &&
      !(kDebugMode && const bool.fromEnvironment('DEV_PREVIEW'));

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
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.bodyWidth),
        child: ListView(
          padding: layout.insets,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('マイページ', style: Theme.of(context).textTheme.headlineSmall),
                // 表示中にも手動で最新の累計を確認できる。
                IconButton(
                  tooltip: '累計を更新',
                  onPressed: _canLoad && !_loading ? _refresh : null,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    _open(
                      SettingsScreen(
                        nickname: _me?['nickname'] as String?,
                        googleEmail: widget.googleEmail,
                      ),
                    );
                  },
                ),
              ],
            ),

            if (_loading) const LinearProgressIndicator(),
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

            const SizedBox(height: 24),

            // プロフィールカード
            Center(
              child: ProfileCard(
                nickname: _me?['nickname'] as String? ?? '未ログイン',
                ideaCount: _me?['ideaCount'] as int? ?? 0,
                drawingCount: _me?['drawnCount'] as int? ?? 0,
                likeCount: _me?['likesReceived'] as int? ?? 0,
              ),
            ),

            const SizedBox(height: 12),

            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.threed_rotation, size: 18),
                SizedBox(width: 8),
                // 狭い画面や大きな文字設定でも説明を折り返す。
                Flexible(child: Text('カードをタップして裏返す')),
              ],
            ),

            const SizedBox(height: 32),

            Text('創作の履歴', style: Theme.of(context).textTheme.titleMedium),

            const SizedBox(height: 12),

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
}
