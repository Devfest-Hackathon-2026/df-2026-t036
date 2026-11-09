import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';
import 'package:illustration_exchange/theme/app_theme.dart';

void main() {
  for (final width in [320.0, 768.0, 1280.0]) {
    testWidgets('idea and saved slots fit at width $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(body: IdeasScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('アイデアノート'), findsOneWidget);
      for (final label in ['自分の投稿', '保存済み']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        expect(boxes.map((box) => box.top).toSet(), hasLength(1));
        for (final box in boxes) {
          expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.5));
          expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.5));
        }
      }

      expect(find.text('アイデアを追加'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('ブックマーク'));
      await tester.pumpAndSettle();
      expect(find.text('保存したアイデア'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('bookmark-slot-5')),
        200,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
  }
}
