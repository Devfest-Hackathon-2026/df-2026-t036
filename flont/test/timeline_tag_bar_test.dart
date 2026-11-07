import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/widgets/timeline_tag_bar.dart';

const tags = [
  '風景',
  'ファンタジー',
  'キャラクター',
  '日常',
  '星',
  '旅',
  '雨',
  '空',
  '月',
  '花',
  '海',
  '図書館',
];
void main() {
  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    testWidgets('tags stay on one horizontal row at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: TimelineTagBar(
                tags: tags,
                selectedTag: null,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('前のタグ'), findsOneWidget);
      expect(find.byTooltip('次のタグ'), findsOneWidget);
      await tester.pumpAndSettle();
      final all = tester.getRect(
        find.byKey(const ValueKey('timeline-tag-all')),
      );
      final last = tester.getRect(
        find.byKey(const ValueKey('timeline-tag-図書館')),
      );
      expect(all.top, closeTo(last.top, 0.01));
      expect(tester.takeException(), isNull);
      if (size.width < 600) {
        await tester.tap(find.byTooltip('次のタグ'));
        await tester.pumpAndSettle();
        final scroll = find.descendant(
          of: find.byKey(const ValueKey('timeline-tag-scroll')),
          matching: find.byType(Scrollable),
        );
        expect(
          tester.state<ScrollableState>(scroll).position.pixels,
          greaterThan(0),
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == '前のタグ',
                ),
              )
              .onPressed,
          isNotNull,
        );
      }
    });
  }
  testWidgets(
    'a tag can be selected and deselected without changing its fixed color',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.topCenter,
                child: TimelineTagBar(
                  tags: tags,
                  selectedTag: selected,
                  onSelected: (tag) => setState(() => selected = tag),
                ),
              ),
            ),
          ),
        ),
      );
      final tag = find.byKey(const ValueKey('timeline-tag-風景'));
      final color = tester
          .widget<Material>(
            find.descendant(of: tag, matching: find.byType(Material)).first,
          )
          .color;
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(selected, '風景');
      expect(tester.widget<Semantics>(tag).properties.selected, isTrue);
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(
        tester
            .widget<Material>(
              find.descendant(of: tag, matching: find.byType(Material)).first,
            )
            .color,
        color,
      );
    },
  );
  testWidgets(
    'Japanese and English labels fit their buttons at enlarged text size',
    (tester) async {
      const labels = ['ファンタジー・キャラクター', 'Fantasy illustration', '風景 Landscape'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(1.5),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: TimelineTagBar(
                  tags: labels,
                  selectedTag: null,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in labels) {
        final button = find.byKey(ValueKey('timeline-tag-$label'));
        final text = find.descendant(
          of: button,
          matching: find.text('#$label'),
        );
        final buttonRect = tester.getRect(button);
        final textRect = tester.getRect(text);
        expect(textRect.left, greaterThanOrEqualTo(buttonRect.left + 16));
        expect(textRect.right, lessThanOrEqualTo(buttonRect.right - 16));
        expect(textRect.top, greaterThanOrEqualTo(buttonRect.top + 5));
        expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom - 5));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
