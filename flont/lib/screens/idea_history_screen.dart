
import 'package:flutter/material.dart';

class IdeaHistoryScreen extends StatelessWidget {
  const IdeaHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アイデア履歴')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.lightbulb_outline),
            title: Text('ファンタジー世界のキャラクター'),
            subtitle: Text('公開中'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.lightbulb_outline),
            title: Text('近未来の街並み'),
            subtitle: Text('ピン受付中'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.lightbulb_outline),
            title: Text('和風のオリジナルキャラクター'),
            subtitle: Text('受付終了'),
          ),
        ],
      ),
    );
  }
}
