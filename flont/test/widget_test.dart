import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/main.dart';
import 'package:illustration_exchange/screens/inbox_screen.dart';
import 'package:illustration_exchange/screens/main_screen.dart';
import 'package:illustration_exchange/screens/profile_screen.dart';
import 'package:illustration_exchange/screens/settings_screen.dart';
import 'package:illustration_exchange/widgets/profile_card.dart';

void main() {
  testWidgets(
    'debugプレビューで認証なしにメイン画面を表示する',
    (tester) async {
      await tester.pumpWidget(const IllustrationExchangeApp());

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.text('タイムライン'), findsOneWidget);
    },
    skip: !const bool.fromEnvironment('DEV_PREVIEW'),
  );

  testWidgets('設定に表示名とGoogleアカウントを表示し対象外項目を出さない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          nickname: 'そらのえふで1234',
          googleEmail: 'artist@example.com',
        ),
      ),
    );

    expect(find.text('表示名'), findsOneWidget);
    expect(find.text('そらのえふで1234'), findsOneWidget);
    expect(find.text('artist@example.com'), findsOneWidget);
    expect(find.text('ログアウト'), findsOneWidget);
    expect(find.text('利用規約'), findsOneWidget);
    expect(find.text('プライバシーポリシー'), findsOneWidget);
    expect(find.text('お問い合わせ'), findsOneWidget);
    expect(find.text('ニックネーム変更'), findsNothing);
    expect(find.text('退会'), findsNothing);
  });

  testWidgets('受信箱の空状態を表示する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: InboxScreen())),
    );

    expect(find.text('受信箱'), findsOneWidget);
    expect(find.text('まだ作品は届いていません'), findsOneWidget);
  });

  testWidgets('登録APIの本人情報をプロフィールへ表示する', (tester) async {
    // サンプル値ではなく、登録された名前と累計が画面へ渡ることを確認する。
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(
          me: {
            'nickname': 'そらのえふで1234',
            'ideaCount': 0,
            'drawnCount': 3,
            'likesReceived': 2,
          },
        ),
      ),
    );
    final card = tester.widget<ProfileCard>(find.byType(ProfileCard));
    expect(card.nickname, 'そらのえふで1234');
    expect(card.ideaCount, 0);
    expect(card.drawingCount, 3);
    expect(card.likeCount, 2);
  });

  testWidgets('プロフィールから設定へ表示名とGoogleアカウントを引き継ぐ', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(
          me: {'nickname': 'そらのえふで1234'},
          googleEmail: 'artist@example.com',
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('そらのえふで1234'), findsOneWidget);
    expect(find.text('artist@example.com'), findsOneWidget);
  });

  testWidgets('基本画面とナビゲーションを表示する', (tester) async {
    await tester.pumpWidget(const IllustrationExchangeApp(home: MainScreen()));

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
    await tester.pumpWidget(const IllustrationExchangeApp(home: MainScreen()));

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
