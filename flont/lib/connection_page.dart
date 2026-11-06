import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'theme/app_theme.dart';

// 接続先はビルド時に指定し、環境ごとのコード変更を不要にする。
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

void main() => runApp(const IllustrationExchangeApp());

class IllustrationExchangeApp extends StatelessWidget {
  const IllustrationExchangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EOCURU',
      // 接続確認画面を単独起動しても同じテーマを使用する。
      theme: AppTheme.light,
      home: const ConnectionPage(),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  String _message = 'ボタンを押してAPIへの接続を確認してください';
  bool _loading = false;

  Future<void> _checkConnection() async {
    setState(() => _loading = true);
    String message;
    try {
      // タイムアウトを設けて、接続できない場合も再試行できるようにする。
      final response = await http
          .get(Uri.parse('${apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/health'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 ||
          (jsonDecode(response.body) as Map<String, dynamic>)['status'] !=
              'ok') {
        throw Exception('APIの応答を確認できませんでした');
      }
      message = 'API接続成功';
    } catch (_) {
      message = 'APIに接続できません。接続先とサーバーの起動を確認してください。';
    }
    // 通信中に画面が破棄された場合は状態を更新しない。
    if (!mounted) return;
    setState(() {
      _message = message;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EOCURU')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_message),
              const SizedBox(height: 16),
              Text('API: $apiBaseUrl'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _checkConnection,
                child: Text(_loading ? '確認中…' : 'API接続確認'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
