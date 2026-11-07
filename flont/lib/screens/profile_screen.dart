import 'package:flutter/material.dart';
import '../theme/page_layout.dart';
import '../widgets/profile_card.dart';
import 'idea_history_screen.dart';
import 'drawing_history_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.me, this.googleEmail, this.apiBaseUrl = 'http://localhost:8080'});

  // ログインしたユーザーの名前と実際の累計を表示する。
  final Map<String, dynamic>? me;
  final String? googleEmail;
  final String apiBaseUrl;

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
                // 本人情報の表示を維持し、設定画面への遷移も取り込む。
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          nickname: me?['nickname'] as String?,
                          googleEmail: googleEmail,
                          apiBaseUrl: apiBaseUrl,
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
                nickname: me?['nickname'] as String? ?? '未ログイン',
                ideaCount: me?['ideaCount'] as int? ?? 0,
                drawingCount: me?['drawnCount'] as int? ?? 0,
                likeCount: me?['likesReceived'] as int? ?? 0,
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const IdeaHistoryScreen(),
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DrawingHistoryScreen(),
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
