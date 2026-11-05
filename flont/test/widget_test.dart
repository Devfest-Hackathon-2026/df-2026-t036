import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/main.dart';

void main() {
  // 初期画面では通信せず、接続確認ボタンを表示する。
  testWidgets('接続確認画面を表示する', (tester) async {
    await tester.pumpWidget(const IllustrationExchangeApp());
    expect(find.text('Illustration Exchange'), findsOneWidget);
    expect(find.text('API接続確認'), findsOneWidget);
  });
}
