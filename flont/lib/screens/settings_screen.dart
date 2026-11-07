import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'terms_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.nickname, this.googleEmail});

  final String? nickname;
  final String? googleEmail;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        content: const Text('この端末からログアウトします。アカウントや保存済みデータは削除されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true && mounted) await _signOut();
  }

  // 認証状態だけを解除し、保存済みのプロフィールや作品は削除しない。
  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      // 設定画面を閉じ、AuthGateが表示するログイン画面へ戻す。
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログアウトできませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final googleEmail =
        widget.googleEmail ?? FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionTitle(context, 'アカウント'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('表示名'),
            subtitle: Text(widget.nickname ?? '取得できません'),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Googleアカウント'),
            subtitle: Text(googleEmail ?? 'メールアドレスを取得できません'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _sectionTitle(context, 'アカウント操作'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(_signingOut ? 'ログアウト中…' : 'ログアウト'),
            subtitle: const Text('この端末からログアウトします'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_signingOut,
            onTap: _signingOut ? null : _confirmSignOut,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _sectionTitle(context, 'サポート'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('利用規約'),
            trailing: const Icon(Icons.chevron_right),
            // 規約全文をアプリ内で閲覧できるようにする。
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (context) => const TermsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('お問い合わせ'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
