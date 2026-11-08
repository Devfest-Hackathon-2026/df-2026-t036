import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/inbox_screen.dart';
import 'package:illustration_exchange/theme/app_theme.dart';
import 'package:illustration_exchange/widgets/received_artwork_card.dart';

void main() {
  testWidgets('opening progress preserves card size and tap handling', (
    tester,
  ) async {
    var taps = 0;
    for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 320,
                child: GestureDetector(
                  onTap: () => taps++,
                  child: ReceivedArtworkCard(
                    title: 'A letter',
                    label: 'Artwork 1',
                    isUnread: true,
                    openingProgress: progress,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ReceivedArtworkCard)),
        const Size(240, 320),
      );
      await tester.tap(find.byType(ReceivedArtworkCard));
      expect(tester.takeException(), isNull);
    }
    expect(taps, 5);
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1280, 720),
  ]) {
    testWidgets('themed inbox fits long titles at text scale 1.5: $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
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
          home: Scaffold(
            appBar: AppBar(title: const Text('EWOCURU')),
            body: const InboxScreen(
              artworkTitles: [
                '月明かりに照らされた青い花が咲く庭と小さな天文台の物語',
                'A small observatory beneath a sky full of midnight stars',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('次の作品'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
