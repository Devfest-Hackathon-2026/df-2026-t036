import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme/page_layout.dart';

/// 受信者が、描き手の公開許可を得た作品から開くプロフィール。
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({
    super.key,
    required this.submissionId,
    required this.apiBaseUrl,
    this.client,
    this.idTokenProvider,
  });

  final String submissionId;
  final String apiBaseUrl;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = false;
  bool _canRetry = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
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
            Uri.parse(
              '$base/api/v1/me/artworks/${Uri.encodeComponent(widget.submissionId)}/artist-profile',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) return;
      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          _canRetry = false;
          throw StateError('プロフィールを表示できません。作品の期限切れ、削除、または公開設定をご確認ください。');
        }
        var message = 'プロフィールを読み込めませんでした。再試行してください。';
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          message = body['error']['message'] as String? ?? message;
        } catch (_) {
          // 読み取れないエラー応答でも、参照不可の情報は推測させない。
        }
        throw StateError(message);
      }
      final profile =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (profile['uid'] is! String ||
          profile['nickname'] is! String ||
          profile['bio'] is! String ||
          profile['socialLinks'] is! List) {
        throw StateError('プロフィールの内容を読み取れませんでした。');
      }
      setState(() => _profile = profile);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'プロフィールを読み込めませんでした。再試行してください。',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openLink(Map<String, dynamic> link) async {
    final url = link['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('外部サイトを開きます'),
        content: Text(uri.host),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('開く'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リンクを開けませんでした。URLを確認してください。')),
      );
    }
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
    final theme = Theme.of(context);
    final links = (_profile?['socialLinks'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('描き手のプロフィール')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.bodyWidth),
          child: ListView(
            padding: layout.insets,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        if (_canRetry)
                          TextButton.icon(
                            onPressed: _loading ? null : _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('再試行'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_profile != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_circle_outlined,
                              size: 36,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _profile!['nickname'] as String,
                                style: theme.textTheme.headlineSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text('自己紹介', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          (_profile!['bio'] as String).isEmpty
                              ? '自己紹介はまだありません'
                              : _profile!['bio'] as String,
                        ),
                        const SizedBox(height: 20),
                        Text('SNSリンク', style: theme.textTheme.titleMedium),
                        if (links.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('SNSリンクは登録されていません'),
                          ),
                        for (final link in links)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.open_in_new),
                            title: Text(link['label'] as String? ?? 'SNS'),
                            subtitle: Text(_host(link['url'] as String? ?? '')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openLink(link),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'この作品の受信者に公開されたプロフィール情報です。',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _host(String url) => Uri.tryParse(url)?.host ?? '';
}
