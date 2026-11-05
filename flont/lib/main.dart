import 'package:flutter/material.dart';
import 'screens/main_screen.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const IllustrationExchangeApp());
}

class IllustrationExchangeApp extends StatelessWidget {
  const IllustrationExchangeApp({super.key});

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
      home: const MainScreen(),
    );
  }
}