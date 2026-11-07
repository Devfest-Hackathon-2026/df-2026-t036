import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/timeline_screen.dart';
import 'package:illustration_exchange/widgets/idea_card.dart';

void main() {
  group('timeline tag preview', () {
    testWidgets(
      'filter searches all samples and all restores the unfiltered list',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TimelineScreen())),
        );
        await tester.pumpAndSettle();
        expect(find.text('すべて / 30件'), findsOneWidget);
        final chip = find.byKey(const ValueKey('timeline-tag-キャラクター'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.text('#キャラクター / 5件'), findsOneWidget);
        for (final card in tester.widgetList<IdeaCard>(find.byType(IdeaCard))) {
          expect(card.tags, contains('キャラクター'));
        }
        await tester.scrollUntilVisible(
          find.text('雲の上で暮らす配達員 28'),
          350,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('雲の上で暮らす配達員 28'), findsOneWidget);
        final all = find.byKey(const ValueKey('timeline-tag-all'));
        await tester.ensureVisible(all);
        await tester.pumpAndSettle();
        await tester.tap(all);
        await tester.pumpAndSettle();
        expect(find.text('すべて / 30件'), findsOneWidget);
        expect(find.text('夜明けを待つ庭 1'), findsOneWidget);
      },
    );
    testWidgets('selecting a tag from page three resets pagination', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TimelineScreen())),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('3'),
        500,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('timeline-tag-風景')));
      await tester.pumpAndSettle();
      expect(find.text('#風景 / 5件'), findsOneWidget);
      expect(find.text('夜明けを待つ庭 1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsNothing);
    });
    testWidgets(
      'deleting an idea retains the selected filter and updates the result count',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TimelineScreen())),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('timeline-tag-風景')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('夜明けを待つ庭 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('idea-delete-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('idea-delete-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('#風景 / 4件'), findsOneWidget);
        expect(find.text('夜明けを待つ庭 1'), findsNothing);
      },
    );
  }, skip: !const bool.fromEnvironment('DEV_PREVIEW'));
}
