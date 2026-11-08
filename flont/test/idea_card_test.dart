import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/theme/app_theme.dart';
import 'package:illustration_exchange/widgets/idea_card.dart';

void main() {
  for (final width in [180.0, 280.0, 390.0]) {
    testWidgets('sketch card fits long titles and tags at width $width', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(1.5),
                    ),
                    child: IdeaCard(
                      sketchStyle: true,
                      title:
                          '夜明けを待つ青い花の庭と小さな天文台 A small observatory beneath the stars',
                      tags: const [
                        'ファンタジー',
                        'IllustrationAndCreativeInspiration',
                      ],
                      statusLabel: '自分のアイデア',
                      date: DateTime(2026, 11, 8),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(IdeaCard)).width, width);
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(IdeaCard));
      for (final text in tester.renderObjectList<RenderBox>(
        find.byType(Text),
      )) {
        final origin = text.localToGlobal(Offset.zero);
        expect(origin.dx, greaterThanOrEqualTo(card.left));
        expect(
          origin.dx + text.size.width,
          lessThanOrEqualTo(card.right + 0.01),
        );
      }
    });
  }

  testWidgets('ribbon saves independently and disabled ribbon cannot save', (
    tester,
  ) async {
    var opened = 0;
    var saved = 0;
    var pinned = false;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return IdeaCard(
                    sketchStyle: true,
                    title: 'An idea',
                    date: DateTime(2026, 11, 8),
                    pinned: pinned,
                    onTap: () => opened++,
                    onPinPressed: enabled
                        ? () {
                            saved++;
                            setState(() => pinned = !pinned);
                          }
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('ブックマークに保存'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(opened, 0);
    expect(find.byTooltip('ブックマークを解除'), findsOneWidget);
    await tester.tap(find.text('An idea'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    update(() => enabled = false);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ブックマークを解除'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(opened, 1);
  });
}
