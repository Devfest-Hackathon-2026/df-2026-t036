import 'package:flutter/gestures.dart';
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

  testWidgets('アイデアカードをスワイプとボタンで切り替える', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    expect(find.text('掲載中 0 / 5'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('枠 1'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('idea-carousel')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('枠 2'), findsOneWidget);

    await tester.tap(find.byTooltip('前のアイデア'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('枠 1'), findsOneWidget);
  });

  testWidgets('マウスクリックでは傾かず空き枠フォームを開く', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );
    final transformFinder = find.byKey(
      const ValueKey('idea-tilt-card-1-transform'),
    );
    final center = tester.getCenter(find.byKey(const ValueKey('idea-slot-1')));

    final click = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedContainer>(transformFinder).transform!.entry(0, 2),
      closeTo(0, 0.001),
    );
    await click.up();
    await tester.pumpAndSettle();

    expect(find.text('アイデアを作成'), findsOneWidget);
  });

  testWidgets('マウスドラッグで次のカードへ進む', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );
    final carousel = find.byKey(const ValueKey('idea-carousel'));
    final center = tester.getCenter(carousel);

    final drag = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(-500, 0));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('画面中央から離れた方向に応じてカードが傾く', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    final carouselRect = tester.getRect(
      find.byKey(const ValueKey('idea-carousel')),
    );
    final drag = await tester.startGesture(carouselRect.center);
    await drag.moveBy(Offset(-carouselRect.width * 0.25, 0));
    await tester.pump();

    final leftCard = find.byKey(const ValueKey('idea-slot-1'));
    final rightCard = find.byKey(const ValueKey('idea-slot-2'));
    expect(tester.getCenter(leftCard).dx, lessThan(carouselRect.center.dx));
    expect(tester.getCenter(rightCard).dx, greaterThan(carouselRect.center.dx));

    final leftRotation = tester
        .widget<AnimatedContainer>(
          find.byKey(const ValueKey('idea-tilt-card-1-transform')),
        )
        .transform!
        .entry(0, 2);
    final rightRotation = tester
        .widget<AnimatedContainer>(
          find.byKey(const ValueKey('idea-tilt-card-2-transform')),
        )
        .transform!
        .entry(0, 2);
    expect(leftRotation, lessThan(0));
    expect(rightRotation, greaterThan(0));
    expect(rightRotation.abs(), greaterThan(leftRotation.abs()));

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('カルーセルの各カードに左右の間隔がある', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    final carouselRect = tester.getRect(
      find.byKey(const ValueKey('idea-carousel')),
    );
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('idea-tilt-card-1-transform')),
    );

    expect(carouselRect.width - cardRect.width, greaterThanOrEqualTo(32));
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
    await tester.tap(find.byKey(const ValueKey('idea-add-tag')));
    await tester.pumpAndSettle();

    final previewButton = find.byKey(const ValueKey('idea-preview-button'));
    await tester.ensureVisible(previewButton);
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

  testWidgets('ページ境界で回転が隣のカードへ連続して移る', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    final carouselRect = tester.getRect(
      find.byKey(const ValueKey('idea-carousel')),
    );
    final drag = await tester.startGesture(carouselRect.center);
    await drag.moveBy(const Offset(-330, 0));
    await tester.pump();

    final previousRotation = tester
        .widget<AnimatedContainer>(
          find.byKey(const ValueKey('idea-tilt-card-1-transform')),
        )
        .transform!
        .entry(0, 2);
    final nextRotation = tester
        .widget<AnimatedContainer>(
          find.byKey(const ValueKey('idea-tilt-card-2-transform')),
        )
        .transform!
        .entry(0, 2);

    expect(previousRotation.abs(), greaterThan(0.02));
    expect(nextRotation.abs(), greaterThan(0.02));
    expect(previousRotation.sign, -nextRotation.sign);
    expect(
      previousRotation.abs() / nextRotation.abs(),
      inInclusiveRange(0.5, 2.0),
    );

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('慣性移動中でも次のカードを続けて回転できる', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    final carousel = find.byKey(const ValueKey('idea-carousel'));
    final carouselRect = tester.getRect(carousel);
    final firstDrag = await tester.startGesture(carouselRect.center);
    await firstDrag.moveBy(const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await firstDrag.up();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('2 / 5'), findsOneWidget);

    final secondCardRect = tester.getRect(
      find.byKey(const ValueKey('idea-slot-2')),
    );
    final secondDrag = await tester.startGesture(
      secondCardRect.intersect(carouselRect).center,
    );
    await secondDrag.moveBy(const Offset(-60, 0));
    await tester.pump();

    final activeSecondCard = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('idea-tilt-card-2-transform')),
    );
    expect(activeSecondCard.duration, Duration.zero);
    expect(activeSecondCard.transform!.entry(0, 2).abs(), greaterThan(0.005));

    await secondDrag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('カードがスマホ画面の高さに広がる', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('idea-carousel'))).height,
      greaterThan(600),
    );
  });

  testWidgets('タッチ位置に合わせてカードが傾き、離すと戻る', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );

    final transformFinder = find.byKey(
      const ValueKey('idea-tilt-card-1-transform'),
    );
    final cardRect = tester.getRect(find.byKey(const ValueKey('idea-slot-1')));
    final gesture = await tester.startGesture(
      Offset(cardRect.left + cardRect.width * 0.2, cardRect.center.dy),
    );
    await gesture.moveBy(const Offset(-100, 4));
    await tester.pump(const Duration(milliseconds: 60));

    final activeCard = tester.widget<AnimatedContainer>(transformFinder);
    expect(activeCard.duration, Duration.zero);
    final tilted = activeCard.transform!;
    expect(tilted.entry(0, 2).abs(), greaterThan(0.02));

    await gesture.up();
    await tester.pumpAndSettle();

    final released = tester
        .widget<AnimatedContainer>(transformFinder)
        .transform!;
    expect(released.entry(0, 2), closeTo(0, 0.001));
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
    expect(find.text('EOCURU'), findsOneWidget);

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
