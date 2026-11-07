import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AuthenticatedApi {
  AuthenticatedApi({
    required this.baseUrl,
    http.Client? client,
    this.idTokenProvider,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final String baseUrl;
  final Future<String?> Function()? idTokenProvider;
  final http.Client _client;
  final bool _ownsClient;

  Future<http.Response> _request(
    String path, {
    bool delete = false,
    Map<String, String>? query,
  }) async {
    final token = idTokenProvider == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : await idTokenProvider!();
    if (token == null || token.isEmpty) throw StateError('再度ログインしてください。');
    final uri = Uri.parse(
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1$path',
    ).replace(queryParameters: query);
    final headers = {'Authorization': 'Bearer $token'};
    final response =
        await (delete
                ? _client.delete(uri, headers: headers)
                : _client.get(uri, headers: headers))
            .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = response.statusCode == 404 ? '参照できません' : '読み込みに失敗しました。';
      if (response.statusCode != 404) {
        try {
          final body =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          message =
              (body['error'] as Map<String, dynamic>)['message'] as String;
        } catch (_) {}
      }
      throw StateError(message);
    }
    return response;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async =>
      jsonDecode(utf8.decode((await _request(path, query: query)).bodyBytes))
          as Map<String, dynamic>;
  Future<void> delete(String path) async {
    await _request(path, delete: true);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
