import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

/// 起動引数を優先し、未指定の項目は同梱したWeb公開設定から読み込む。
class AppConfig {
  AppConfig._(this.values);

  final Map<String, String> values;

  static Future<AppConfig> load({
    AssetBundle? bundle,
    Map<String, String> overrides = const {
      'FIREBASE_API_KEY': String.fromEnvironment('FIREBASE_API_KEY'),
      'FIREBASE_APP_ID': String.fromEnvironment('FIREBASE_APP_ID'),
      'FIREBASE_MESSAGING_SENDER_ID': String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
      ),
      'FIREBASE_PROJECT_ID': String.fromEnvironment('FIREBASE_PROJECT_ID'),
      'FIREBASE_AUTH_DOMAIN': String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
    },
  }) async {
    final values = <String, String>{};
    final requiredKeys = [
      'FIREBASE_API_KEY',
      'FIREBASE_APP_ID',
      'FIREBASE_MESSAGING_SENDER_ID',
      'FIREBASE_PROJECT_ID',
      'FIREBASE_AUTH_DOMAIN',
    ];
    // 全設定を明示したビルドでは、ローカル設定の内容に依存しない。
    if (requiredKeys.any((key) => (overrides[key] ?? '').isEmpty)) {
      try {
        final json =
            jsonDecode(
                  await (bundle ?? rootBundle).loadString(
                    'firebase-config.local.json',
                  ),
                )
                as Map<String, dynamic>;
        for (final entry in json.entries) {
          if (entry.value is String) {
            values[entry.key] = (entry.value as String).trim();
          }
        }
      } catch (_) {
        throw StateError(
          'firebase-config.local.jsonを読み込めません。flont/README.mdの初回設定を確認してください。',
        );
      }
    }
    for (final entry in overrides.entries) {
      if (entry.value.trim().isNotEmpty) values[entry.key] = entry.value.trim();
    }
    if (requiredKeys.any((key) {
      final value = values[key] ?? '';
      return value.isEmpty || RegExp(r'YOUR_|your-|REPLACE').hasMatch(value);
    })) {
      throw StateError(
        'firebase-config.local.jsonにFirebaseのWeb設定を入力してください。flont/README.mdを参照してください。',
      );
    }
    return AppConfig._(values);
  }

  FirebaseOptions get firebaseOptions => FirebaseOptions(
    apiKey: values['FIREBASE_API_KEY']!,
    appId: values['FIREBASE_APP_ID']!,
    messagingSenderId: values['FIREBASE_MESSAGING_SENDER_ID']!,
    projectId: values['FIREBASE_PROJECT_ID']!,
    authDomain: values['FIREBASE_AUTH_DOMAIN']!,
  );

  String get apiBaseUrl => values['API_BASE_URL'] ?? 'http://localhost:8080';
}
