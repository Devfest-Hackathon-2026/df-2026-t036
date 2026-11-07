import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/timeline_screen.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';
import 'package:illustration_exchange/screens/idea_detail_screen.dart';

void main() {
  // プレビューで保存解除したお題が、タブ切り替えで復活しないことを確認する。
  testWidgets('プレビューの保存解除を切り替え後も維持する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );
    await tester.tap(find.byTooltip('ブックマーク'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ブックマークを解除').first);
    await tester.pumpAndSettle();
    expect(find.text('雨の日だけ開く喫茶店'), findsNothing);
    await tester.tap(find.byTooltip('自分のアイデア'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ブックマーク'));
    await tester.pumpAndSettle();
    expect(find.text('雨の日だけ開く喫茶店'), findsNothing);
    expect(find.text('海の底にある図書館'), findsOneWidget);
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));
  // 受付可否に従ってボタンを出し分け、未実装の送信を成功扱いにしない。
  for (final eligible in [true, false]) {
    testWidgets('送信可否 $eligible に合わせて送信ボタンを表示する', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IdeaDetailScreen(
            idea: IdeaSlotData(
              ideaId: 'test',
              title: 'テストのお題',
              expiresAt: DateTime.now().add(const Duration(days: 1)),
              previewDescription: '本文',
            ),
            apiBaseUrl: '',
            authenticated: false,
            preview: true,
            previewCanSubmit: eligible,
          ),
        ),
      );
      final button = find.byKey(const ValueKey('idea-send-artwork-button'));
      expect(button, eligible ? findsOneWidget : findsNothing);
      if (eligible) {
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('UIプレビュー・実際には送信されません'), findsOneWidget);
      }
    });
  }
  // 対象カードの内容が開き、他人のお題には削除ボタンがないことを確認する。
  testWidgets('TLで選んだお題の詳細が開く', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TimelineScreen())),
    );
    await tester.tap(find.byKey(const ValueKey('preview-idea-1')));
    await tester.pumpAndSettle();
    expect(find.byType(IdeaDetailScreen), findsOneWidget);
    expect(find.text('旅する小さな天文台 2'), findsOneWidget);
    expect(find.text('このお題に合わせたイラストを描いてみてください。'), findsOneWidget);
    expect(find.byKey(const ValueKey('idea-delete-button')), findsNothing);
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));

  testWidgets('ブックマークから対応した詳細を開く', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IdeasScreen())),
    );
    await tester.tap(find.byTooltip('ブックマーク'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bookmark-slot-1')));
    await tester.pumpAndSettle();
    expect(find.byType(IdeaDetailScreen), findsOneWidget);
    expect(find.text('雨の日だけ開く喫茶店'), findsOneWidget);
    expect(find.text('ブックマークしたお題のプレビューです。'), findsOneWidget);
    expect(find.byKey(const ValueKey('idea-delete-button')), findsNothing);
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));
}
