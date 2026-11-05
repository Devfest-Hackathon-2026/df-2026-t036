import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/main.dart';

void main() {
  testWidgets('基本画面とナビゲーションを表示する', (tester) async {
    await tester.pumpWidget(
      const IllustrationExchangeApp(),
    );

    // 上部のアプリ名を確認
    expect(find.text('Illustration Exchange'), findsOneWidget);

    // 下部の4つのナビゲーションを確認
    expect(find.text('タイムライン'), findsOneWidget);
    expect(find.text('アイデア'), findsOneWidget);
    expect(find.text('受信箱'), findsOneWidget);
    expect(find.text('マイページ'), findsOneWidget);

    // ナビゲーションが4つ存在することを確認
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('ナビゲーションを切り替えられる', (tester) async {
    await tester.pumpWidget(
      const IllustrationExchangeApp(),
    );

    // アイデアタブをタップ
    await tester.tap(find.text('アイデア'));
    await tester.pumpAndSettle();

    // アイデアタブが選択されていることを確認
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );

    expect(navigationBar.selectedIndex, 1);
  });
}