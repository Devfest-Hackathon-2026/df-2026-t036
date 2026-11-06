import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/config/app_config.dart';

// 個人のFirebase設定を使わず、JSONの読み込みと引数の優先順位を検証する。
class ConfigBundle extends CachingAssetBundle {
  ConfigBundle(this.content);
  final String content;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
}

void main() {
  const values = {
    'FIREBASE_API_KEY': 'test-key',
    'FIREBASE_APP_ID': 'test-app',
    'FIREBASE_MESSAGING_SENDER_ID': '123',
    'FIREBASE_PROJECT_ID': 'test-project',
    'FIREBASE_AUTH_DOMAIN': 'test-project.firebaseapp.com',
    'API_BASE_URL': 'http://localhost:8081',
  };

  test('引数なしでJSONからFirebase設定とAPI接続先を読む', () async {
    final config = await AppConfig.load(
      bundle: ConfigBundle(jsonEncode(values)),
      overrides: {},
    );
    expect(config.firebaseOptions.projectId, 'test-project');
    expect(config.apiBaseUrl, 'http://localhost:8081');
  });

  test('起動引数がJSONの該当項目より優先される', () async {
    final config = await AppConfig.load(
      bundle: ConfigBundle(jsonEncode(values)),
      overrides: {'FIREBASE_PROJECT_ID': 'override-project'},
    );
    expect(config.firebaseOptions.projectId, 'override-project');
    expect(config.firebaseOptions.apiKey, 'test-key');
  });

  test('設定を全て明示した場合は不正なJSONに依存しない', () async {
    final config = await AppConfig.load(
      bundle: ConfigBundle('invalid'),
      overrides: values,
    );
    expect(config.firebaseOptions.projectId, 'test-project');
  });

  test('サンプル値や不正なJSONは設定エラーにする', () async {
    for (final content in [
      jsonEncode({...values, 'FIREBASE_API_KEY': 'YOUR_API_KEY'}),
      'invalid',
    ]) {
      await expectLater(
        AppConfig.load(bundle: ConfigBundle(content), overrides: {}),
        throwsStateError,
      );
    }
  });
}
