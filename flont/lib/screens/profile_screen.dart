
import 'package:flutter/material.dart';
import '../widgets/profile_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'マイページ',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Icon(Icons.settings_outlined),
              ],
            ),

            const SizedBox(height: 24),

            // プロフィールカード
            const Center(
              child: ProfileCard(
                nickname: 'サンプルユーザー',
                ideaCount: 12,
                drawingCount: 8,
                likeCount: 24,
              ),
            ),

            const SizedBox(height: 12),

            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.threed_rotation, size: 18),
                SizedBox(width: 8),
                Text('カードをタップして裏返す'),
              ],
            ),

            const SizedBox(height: 32),

            Text(
              '創作の履歴',
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 12),

            const Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.lightbulb_outline),
                    title: Text('アイデア履歴'),
                    subtitle: Text('投稿したお題を確認する'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.brush_outlined),
                    title: Text('描いた履歴'),
                    subtitle: Text('参加したお題を振り返る'),
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
