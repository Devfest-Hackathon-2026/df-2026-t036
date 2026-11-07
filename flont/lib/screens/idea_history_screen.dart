import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'history_screen.dart';

class IdeaHistoryScreen extends StatelessWidget {
  const IdeaHistoryScreen({
    super.key,
    this.apiBaseUrl = 'http://localhost:8080',
    this.authenticated = false,
    this.client,
    this.idTokenProvider,
  });

  // 本人の履歴だけを認証済みAPIから取得する。
  final String apiBaseUrl;
  final bool authenticated;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      drawn: false,
      apiBaseUrl: apiBaseUrl,
      authenticated: authenticated,
      client: client,
      idTokenProvider: idTokenProvider,
    );
  }
}
