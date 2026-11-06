import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'package:google_fonts/google_fonts.dart';

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
      home: home ?? const AuthGate(),
    );
  }
}
