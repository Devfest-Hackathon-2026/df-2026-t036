import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/inbox_screen.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';

void main() {
  // 受信カードの輪郭が幅にかかわらず横3・縦4になることを確認する。
  testWidgets('受信カードは3対4で表示される', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InboxScreen(artworkTitles: ['作品A'])),
      ),
    );
    final size = tester.getSize(find.byType(IdeaSlotCard));
    expect(size.width / size.height, closeTo(3 / 4, 0.001));
  });
  // 作品数に応じた操作表示と、実際に次の作品へ移れることを確認する。
  testWidgets('一作品では切り替えフッターを表示しない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InboxScreen(artworkTitles: ['作品A'])),
      ),
    );
    expect(find.text('作品A'), findsOneWidget);
    expect(find.byTooltip('次の作品'), findsNothing);
  });

  testWidgets('複数作品では本文内のフッターで次のカードに移動できる', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InboxScreen(artworkTitles: ['作品A', '作品B'])),
      ),
    );
    expect(find.text('1 / 2'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byTooltip('次の作品'),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byTooltip('次の作品'));
    await tester.tap(find.byTooltip('次の作品'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('作品B'), findsOneWidget);
  });
  // スライド中は共通カードが回転し、停止後には正面へ戻る。
  testWidgets('受信カードがスライド中に傾き、停止後に戻る', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InboxScreen(artworkTitles: ['作品A', '作品B'])),
      ),
    );
    final pageView = find.byType(PageView);
    final gesture = await tester.startGesture(tester.getCenter(pageView));
    // 最初の移動でドラッグ判定を開始し、次の移動でスライドさせる。
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-120, 12));
    await tester.pump();
    final tilted = tester.widget<Transform>(
      find.byKey(const ValueKey('inbox-tilt-0-transform')),
    );
    expect(tilted.transform.entry(0, 2).abs(), greaterThan(0.001));
    await gesture.up();
    await tester.pumpAndSettle();
    final page = tester.widget<PageView>(pageView).controller!.page!.round();
    final settled = tester.widget<Transform>(
      find.byKey(ValueKey('inbox-tilt-$page-transform')),
    );
    expect(settled.transform.entry(0, 2), closeTo(0, 0.001));
  });
  // 透視付きの復帰アニメーション中も行列とマウス位置判定を検証する。
  testWidgets('傾きの復帰中に行列がNaNにならず入力を受け付ける', (tester) async {
    final angle = ValueNotifier<double>(0.1);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: angle,
              builder: (context, value, child) => TiltCard(
                key: const ValueKey('regression'),
                rotationX: value,
                rotationY: value,
                isDragging: false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox(width: 240, height: 320),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    angle.value = 0;
    await tester.pump();
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('regression-transform')),
      );
      expect(
        transform.transform.storage.every((value) => value.isFinite),
        isTrue,
      );
      expect(transform.transformHitTests, isFalse);
      await tester.tap(find.byKey(const ValueKey('regression-transform')));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    expect(taps, 30);
    angle.dispose();
  });
}
