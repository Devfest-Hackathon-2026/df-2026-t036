import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/idea_history_screen.dart';
import 'package:illustration_exchange/screens/drawing_history_screen.dart';
import 'package:illustration_exchange/screens/idea_detail_screen.dart';
import 'package:illustration_exchange/widgets/idea_card.dart';

void main() {
  group('history previews', () {
    testWidgets(
      'own history opens detail and deletion survives a manual refresh',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: IdeaHistoryScreen()));
        await tester.pumpAndSettle();
        expect(find.text('掲載中'), findsOneWidget);
        expect(find.text('ピン受付中'), findsOneWidget);
        expect(find.text('受付終了'), findsOneWidget);
        await tester.tap(find.byType(IdeaCard).first);
        await tester.pumpAndSettle();
        expect(find.byType(IdeaDetailScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('idea-delete-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('idea-delete-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(IdeaCard), findsNWidgets(2));
        await tester.tap(find.byTooltip('履歴を更新'));
        await tester.pumpAndSettle();
        expect(find.byType(IdeaCard), findsNWidgets(2));
      },
    );
    testWidgets(
      'drawing preview shows unavailable history without artwork images or deletion',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: DrawingHistoryScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.text('参照できません'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        await tester.tap(find.byType(IdeaCard).first);
        await tester.pumpAndSettle();
        expect(find.byType(IdeaDetailScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('idea-delete-button')), findsNothing);
        expect(
          find.byKey(const ValueKey('idea-send-artwork-button')),
          findsNothing,
        );
      },
    );
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));
}
