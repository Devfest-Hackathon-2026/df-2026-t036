import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/widgets/card_hover_glow.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets('hover glow cleans up; reduced motion: $reduceMotion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: const Scaffold(
              body: Center(
                child: CardHoverGlow(
                  color: Colors.blue,
                  radius: 12,
                  child: SizedBox(width: 200, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(CardHoverGlow)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.foregroundDecoration! as BoxDecoration;
      expect(decoration.border!.top.color.a, greaterThan(0));
      expect(tester.hasRunningAnimations, !reduceMotion);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      await mouse.moveTo(tester.getCenter(find.byType(CardHoverGlow)));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }
}
