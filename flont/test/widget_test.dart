import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/main.dart';
import 'package:illustration_exchange/screens/idea_composer_screen.dart';
import 'package:illustration_exchange/screens/idea_detail_screen.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';
import 'package:illustration_exchange/screens/inbox_screen.dart';
import 'package:illustration_exchange/screens/main_screen.dart';
import 'package:illustration_exchange/screens/profile_screen.dart';
import 'package:illustration_exchange/screens/settings_screen.dart';
import 'package:illustration_exchange/widgets/profile_card.dart';

void main() {
  // 保存済み表示から戻っても、自分の投稿枠を維持する。
  testWidgets('自分のアイデアとブックマークを切り替える', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );
    expect(find.byKey(const ValueKey('idea-slot-1')), findsOneWidget);
    await tester.tap(find.byTooltip('ブックマーク'));
    await tester.pumpAndSettle();
    expect(find.text('ブックマークしたアイデアはありません。'), findsNothing);
    expect(find.byKey(const ValueKey('idea-slot-1')), findsNothing);
    final lastBookmark = find.byKey(const ValueKey('bookmark-slot-5'));
    // 空の状態でも五枠目まで縦に表示される。
    await tester.scrollUntilVisible(lastBookmark, 200);
    await tester.pumpAndSettle();
    expect(lastBookmark, findsOneWidget);
    await tester.scrollUntilVisible(find.byTooltip('自分のアイデア'), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('自分のアイデア'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('idea-slot-1')), findsOneWidget);
  });
  // 五つの枠が同じ横位置に並び、下の空き枠まで縦スクロールできる。
  testWidgets('アイデア枠を縦一列で五枠表示する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );
    expect(find.byType(PageView), findsNothing);
    final first = find.byKey(const ValueKey('idea-slot-1'));
    final second = find.byKey(const ValueKey('idea-slot-2'));
    expect(
      tester.getTopLeft(second).dy,
      greaterThan(tester.getBottomLeft(first).dy),
    );
    expect(tester.getTopLeft(first).dx, tester.getTopLeft(second).dx);
    final last = find.byKey(const ValueKey('idea-slot-5'));
    // 画面外でまだ構築されていない枠までスクロールする。
    await tester.scrollUntilVisible(last, 200);
    // スクロール後の描画位置を確定してから操作する。
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('idea-slot-5')), findsOneWidget);
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.text('アイデアを作成'), findsOneWidget);
  });
  testWidgets('debugプレビューで認証なしにメイン画面を表示する', (tester) async {
    await tester.pumpWidget(const IllustrationExchangeApp());

    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.text('タイムライン'), findsOneWidget);
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));

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
    // デモ追加後も、画面下部の項目へスクロールして確認する。
    await tester.scrollUntilVisible(find.text('お問い合わせ'), 200);
    await tester.pumpAndSettle();
    expect(find.text('お問い合わせ'), findsOneWidget);
    expect(find.text('ニックネーム変更'), findsNothing);
    expect(find.text('退会'), findsNothing);
  });

  testWidgets('ログアウトをキャンセルすると設定画面に戻る', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(
          nickname: 'そらのえふで1234',
          googleEmail: 'artist@example.com',
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ListTile, 'ログアウト'));
    await tester.pumpAndSettle();

    expect(find.text('ログアウトしますか？'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('そらのえふで1234'), findsOneWidget);
  });

  testWidgets('受信箱の空状態を表示する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: InboxScreen())),
    );

    expect(find.text('受信箱'), findsOneWidget);
    expect(find.text('まだ作品は届いていません'), findsOneWidget);
  });

  testWidgets('アイデアを確認プレビューしてから投稿する', (tester) async {
    IdeaDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: IdeaComposerScreen(onSubmit: (draft) async => submitted = draft),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('idea-title-input')),
      '雨の日の小さな喫茶店',
    );
    await tester.enterText(
      find.byKey(const ValueKey('idea-description-input')),
      '窓辺で本を読む猫と、湯気の立つココア。',
    );
    await tester.enterText(find.byKey(const ValueKey('idea-tag-input')), '日常');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('idea-add-tag')));
    await tester.pumpAndSettle();

    final previewButton = find.byKey(const ValueKey('idea-preview-button'));
    await tester.scrollUntilVisible(
      previewButton,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(previewButton);
    await tester.pumpAndSettle();
    expect(find.text('投稿内容の確認'), findsOneWidget);
    expect(find.text('雨の日の小さな喫茶店'), findsOneWidget);
    expect(find.text('投稿後は内容を編集できません。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('idea-submit-button')));
    await tester.pumpAndSettle();

    expect(submitted?.title, '雨の日の小さな喫茶店');
    expect(submitted?.description, '窓辺で本を読む猫と、湯気の立つココア。');
    expect(submitted?.tags, ['日常']);
  });

  testWidgets('空き枠を選ぶとアイデア作成フォームを開く', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    await tester.tap(find.byKey(const ValueKey('idea-slot-1')));
    await tester.pumpAndSettle();

    expect(find.text('アイデアを作成'), findsOneWidget);
    expect(find.byKey(const ValueKey('idea-title-input')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('idea-description-input')),
      findsOneWidget,
    );
  });

  testWidgets('アイデア詳細に説明・タグ・掲載残り時間を表示する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IdeaDetailScreen(
          idea: IdeaSlotData(
            ideaId: 'preview-idea',
            title: '夜明けを待つ庭',
            expiresAt: DateTime.now().add(const Duration(days: 3, hours: 2)),
            previewDescription: '青い花が咲く庭に、朝日が差し込む景色。',
            previewTags: const ['風景', 'ファンタジー'],
          ),
          apiBaseUrl: 'http://localhost:8080',
          authenticated: false,
          onDelete: () async {},
          preview: true,
        ),
      ),
    );

    expect(find.text('夜明けを待つ庭'), findsOneWidget);
    expect(find.text('青い花が咲く庭に、朝日が差し込む景色。'), findsOneWidget);
    expect(find.text('風景'), findsOneWidget);
    expect(find.text('ファンタジー'), findsOneWidget);
    expect(find.textContaining('掲載終了まであと3日'), findsOneWidget);
  });

  testWidgets('確認後だけアイデア削除を実行する', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => IdeaDetailScreen(
                      idea: IdeaSlotData(
                        ideaId: 'preview-idea',
                        title: '夜明けを待つ庭',
                        expiresAt: DateTime.now().add(const Duration(days: 3)),
                        previewDescription: '青い花が咲く庭。',
                      ),
                      apiBaseUrl: 'http://localhost:8080',
                      authenticated: false,
                      onDelete: () async => deleted = true,
                      preview: true,
                    ),
                  ),
                ),
                child: const Text('詳細を開く'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('詳細を開く'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('idea-delete-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('idea-delete-button')));
    await tester.pumpAndSettle();

    expect(find.text('アイデアを削除しますか？'), findsOneWidget);
    expect(deleted, isFalse);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);

    await tester.tap(find.byKey(const ValueKey('idea-delete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('idea-delete-confirm')));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('詳細を開く'), findsOneWidget);
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
    expect(
      find.image(const AssetImage('assets/images/logo.png')),
      findsOneWidget,
    );

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
  testWidgets('tabs are built on first visit and retain state', (tester) async {
    await tester.pumpWidget(const IllustrationExchangeApp(home: MainScreen()));
    expect(find.byType(IdeasScreen, skipOffstage: false), findsNothing);
    expect(find.byType(InboxScreen, skipOffstage: false), findsNothing);
    expect(find.byType(ProfileScreen, skipOffstage: false), findsNothing);
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    final initialState = tester.state(find.byType(IdeasScreen));
    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(IdeasScreen)), same(initialState));
  });
}
