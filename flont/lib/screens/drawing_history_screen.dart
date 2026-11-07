import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'history_screen.dart';

class DrawingHistoryScreen extends StatelessWidget {
  const DrawingHistoryScreen({
    super.key,
    this.apiBaseUrl = 'http://localhost:8080',
    this.authenticated = false,
    this.client,
    this.idTokenProvider,
  });

  // 作品画像を含めず、送信先のお題と最終いいね状態を表示する。
  final String apiBaseUrl;
  final bool authenticated;
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      drawn: true,
      apiBaseUrl: apiBaseUrl,
      authenticated: authenticated,
      client: client,
      idTokenProvider: idTokenProvider,
    );
  }
}
