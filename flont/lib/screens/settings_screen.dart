import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

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
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          ListTile(leading: Icon(Icons.edit_outlined), title: Text('ニックネーム変更')),
          ListTile(
            leading: Icon(Icons.account_circle_outlined),
            title: Text('Googleアカウント情報'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.logout),
            title: Text(_signingOut ? 'ログアウト中…' : 'ログアウト'),
            enabled: !_signingOut,
            onTap: _signingOut ? null : _signOut,
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined),
            title: Text('退会'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('利用規約'),
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('プライバシーポリシー'),
          ),
          ListTile(leading: Icon(Icons.mail_outline), title: Text('お問い合わせ')),
        ],
      ),
    );
  }
}
