import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/authenticated_api.dart';
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
    this.active = false,
    this.client,
    this.idTokenProvider,
  });

  // ログインしたユーザーの名前と実際の累計を表示する。
  final Map<String, dynamic>? me;
  final String? googleEmail;
  final String apiBaseUrl;

  final bool active;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Map<String, dynamic>? _me = widget.me;
  late AuthenticatedApi _api = _makeApi();
  AuthenticatedApi _makeApi() => AuthenticatedApi(
    baseUrl: widget.apiBaseUrl,
    client: widget.client,
    idTokenProvider: widget.idTokenProvider,
  );
  bool _loading = false;
  String? _error;
  int _generation = 0;
  bool get _preview => kDebugMode && const bool.fromEnvironment('DEV_PREVIEW');
  @override
  void initState() {
    super.initState();
    if (widget.active) _refreshMe();
  }

  @override
  void dispose() {
    _generation++;
    _api.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.me != widget.me) {
      _generation++;
      _api.dispose();
      _api = _makeApi();
      _me = widget.me;
      _error = null;
      _loading = false;
      if (widget.active) _refreshMe();
    } else if (oldWidget.active != widget.active) {
      _generation++;
      _loading = false;
      if (widget.active) _refreshMe();
    }
  }

  Future<void> _refreshMe() async {
    if (_preview || widget.me == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await _api.get('/me');
      // Reject malformed responses while retaining the last known profile.
      if (me['nickname'] is! String ||
          me['ideaCount'] is! int ||
          me['drawnCount'] is! int ||
          me['likesReceived'] is! int) {
        throw const FormatException('Invalid profile');
      }
      if (mounted && generation == _generation) setState(() => _me = me);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '本人情報を更新できませんでした。',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openHistory(bool drawing) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => drawing
            ? DrawingHistoryScreen(
                apiBaseUrl: widget.apiBaseUrl,
                authenticated: widget.me != null,
                client: widget.client,
                idTokenProvider: widget.idTokenProvider,
              )
            : IdeaHistoryScreen(
                apiBaseUrl: widget.apiBaseUrl,
                authenticated: widget.me != null,
                client: widget.client,
                idTokenProvider: widget.idTokenProvider,
              ),
      ),
    );
    if (mounted) _refreshMe();
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
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _loading ? null : _refreshMe,
                    child: const Text('再試行'),
                  ),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('マイページ', style: Theme.of(context).textTheme.headlineSmall),
                // 本人情報の表示を維持し、設定画面への遷移も取り込む。
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          nickname: _me?['nickname'] as String?,
                          googleEmail: widget.googleEmail,
                          apiBaseUrl: widget.apiBaseUrl,
                        ),
                      ),
                    );
                  },
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
                    onTap: () => _openHistory(false),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.brush_outlined),
                    title: const Text('描いた履歴'),
                    subtitle: const Text('参加したお題を振り返る'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openHistory(true),
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
