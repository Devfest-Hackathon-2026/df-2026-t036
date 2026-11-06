
import 'package:flutter/material.dart';

class DrawingHistoryScreen extends StatelessWidget {
  const DrawingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('描いた履歴')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.brush_outlined),
            title: Text('魔法使いの女の子'),
            subtitle: Text('イラスト送信済み'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.brush_outlined),
            title: Text('森の中の小さな家'),
            subtitle: Text('イラスト送信済み'),
          ),
        ],
      ),
    );
  }
}
