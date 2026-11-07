import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:illustration_exchange/screens/main_screen.dart';
import 'auth_gate.dart';
import 'theme/app_theme.dart';
import 'theme/app_scroll_behavior.dart';

const _developmentPreview = bool.fromEnvironment('DEV_PREVIEW');

void main() {
  runApp(const IllustrationExchangeApp());
}

class IllustrationExchangeApp extends StatelessWidget {
  const IllustrationExchangeApp({super.key, this.home});

  // 画面単体のテストでは認証サービスへの接続を差し替えられる。
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    // 共通テーマをルートで設定し、遷移先の画面にも継承する。
    return MaterialApp(
      // アプリ切替やブラウザで使用する表示名。
      title: 'EOCURU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 一覧や遷移先も含め、スクロール操作とバーの表示方針を統一する。
      scrollBehavior: const AppScrollBehavior(),
      // 開発プレビューはデバッグ時だけ有効にし、通常は認証画面から開始する。
      home:
          home ??
          (kDebugMode && _developmentPreview
              ? const Banner(
                  message: 'プレビュー',
                  location: BannerLocation.topEnd,
                  child: MainScreen(
                    me: {
                      'uid': 'preview-user',
                      'nickname': 'プレビュー利用者',
                      'status': 'active',
                      'ideaCount': 2,
                      'drawnCount': 4,
                      'likesReceived': 3,
                    },
                    googleEmail: 'preview@example.test',
                  ),
                )
              : const AuthGate()),
    );
  }
}
