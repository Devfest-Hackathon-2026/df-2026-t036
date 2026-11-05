import 'package:flutter/material.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const IllustrationExchangeApp());
}

class IllustrationExchangeApp extends StatelessWidget {
  const IllustrationExchangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Illustration Exchange',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const MainScreen(),
    );
  }
}