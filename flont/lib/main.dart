import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:illustration_exchange/screens/main_screen.dart';
import 'auth_gate.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.indigo,
    );
    return MaterialApp(
      title: 'Illustration Exchange',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          fontFamily: GoogleFonts.mPlusRounded1c().fontFamily,
        ),
      ),
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
