import 'package:flutter/material.dart';
import 'package:illustration_exchange/screens/main_screen.dart';
import 'auth_gate.dart';
import 'theme/app_theme.dart';
import 'theme/app_scroll_behavior.dart';
import 'widgets/font_loading_gate.dart';

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
      // アプリの表示名を正式なサービス名に揃える。
      title: 'EWOCURU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 一覧や遷移先も含め、スクロール操作とバーの表示方針を統一する。
      scrollBehavior: const AppScrollBehavior(),
      // DEV_PREVIEWを明示した時だけサンプルを表示し、通常は認証画面から開始する。
      home:
          home ??
          FontLoadingGate(
            child: (_developmentPreview
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
                        'bio': '水彩と色鉛筆で、物語のある風景を描いています。',
                        'socialLinks': [
                          {
                            'type': 'pixiv',
                            'label': 'pixiv',
                            'url': 'https://www.pixiv.net/users/example',
                          },
                          {
                            'type': 'x',
                            'label': 'X',
                            'url': 'https://x.com/example',
                          },
                        ],
                      },
                      googleEmail: 'preview@example.test',
                    ),
                  )
                : const AuthGate()),
          ),
    );
  }
}
