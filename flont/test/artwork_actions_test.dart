import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/widgets/artwork_actions.dart';

Widget actions({VoidCallback? like, VoidCallback? save, bool liked = false}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: ArtworkActions(
              liked: liked,
              onLike: like,
              onSave: save,
              child: const SizedBox(
                height: 300,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
void main() {
  for (final name in ['like', 'save']) {
    testWidgets('long press slide and release selects $name once', (
      tester,
    ) async {
      final counts = <String, int>{};
      void count(String name) =>
          counts.update(name, (value) => value + 1, ifAbsent: () => 1);
      await tester.pumpWidget(
        actions(like: () => count('like'), save: () => count('save')),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('artwork-long-press'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final target = find.byKey(ValueKey('quick-action-$name'));
      expect(target, findsOneWidget);
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      expect(counts, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(counts, {name: 1});
      expect(find.byKey(ValueKey('quick-action-$name')), findsNothing);
    });
  }
  testWidgets('releasing outside all actions cancels', (tester) async {
    var calls = 0;
    await tester.pumpWidget(actions(like: () => calls++));
    final center = tester.getCenter(
      find.byKey(const ValueKey('artwork-long-press')),
    );
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(const Offset(20, 550));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byKey(const ValueKey('quick-action-like')), findsNothing);
  });
  testWidgets('visible buttons use the same actions', (tester) async {
    var likes = 0;
    var saves = 0;
    await tester.pumpWidget(actions(like: () => likes++, save: () => saves++));
    await tester.tap(find.byKey(const ValueKey('artwork-action-like')));
    await tester.tap(find.byKey(const ValueKey('artwork-action-save')));
    expect([likes, saves], [1, 1]);
  });
  testWidgets('menu stays inside a phone screen near its edge', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(actions(like: () {}, save: () {}));
    final rect = tester.getRect(
      find.byKey(const ValueKey('artwork-long-press')),
    );
    final gesture = await tester.startGesture(
      rect.topLeft + const Offset(3, 3),
    );
    await tester.pump(const Duration(milliseconds: 600));
    for (final name in ['like', 'save']) {
      final target = tester.getRect(find.byKey(ValueKey('quick-action-$name')));
      expect(target.left, greaterThanOrEqualTo(0));
      expect(target.right, lessThanOrEqualTo(390));
      expect(target.top, greaterThanOrEqualTo(0));
      expect(target.bottom, lessThanOrEqualTo(844));
    }
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-action-like')), findsNothing);
  });
  testWidgets('disabling actions closes an open menu safely', (tester) async {
    await tester.pumpWidget(actions(like: () {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('artwork-long-press'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(actions(liked: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('quick-action-like')), findsNothing);
    expect(tester.takeException(), isNull);
    await gesture.cancel();
    await tester.pumpWidget(const SizedBox());
  });
}
