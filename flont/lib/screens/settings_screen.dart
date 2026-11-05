
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('ニックネーム変更'),
          ),
          ListTile(
            leading: Icon(Icons.account_circle_outlined),
            title: Text('Googleアカウント情報'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.logout),
            title: Text('ログアウト'),
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
          ListTile(
            leading: Icon(Icons.mail_outline),
            title: Text('お問い合わせ'),
          ),
        ],
      ),
    );
  }
}
