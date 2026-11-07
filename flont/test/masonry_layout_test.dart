import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/widgets/masonry_layout.dart';

void main() {
  testWidgets(
    'short cards fill gaps below their column rather than waiting for a row',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: MasonryLayout(
                  columns: 2,
                  children: [
                    SizedBox(key: ValueKey('tall'), height: 180),
                    SizedBox(key: ValueKey('short'), height: 80),
                    SizedBox(key: ValueKey('next'), height: 70),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final short = tester.getRect(find.byKey(const ValueKey('short')));
      final next = tester.getRect(find.byKey(const ValueKey('next')));
      expect(next.left, short.left);
      expect(next.top, short.bottom + 12);
      expect(
        next.top,
        lessThan(tester.getRect(find.byKey(const ValueKey('tall'))).bottom),
      );
    },
  );
  testWidgets('image aspect ratio changes trigger a fresh gap-free layout', (
    tester,
  ) async {
    var ratio = 2.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return MasonryLayout(
                    columns: 2,
                    children: [
                      AspectRatio(
                        key: const ValueKey('image'),
                        aspectRatio: ratio,
                        child: const ColoredBox(color: Colors.blue),
                      ),
                      const SizedBox(key: ValueKey('second'), height: 200),
                      const SizedBox(key: ValueKey('third'), height: 40),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    var image = tester.getRect(find.byKey(const ValueKey('image')));
    var third = tester.getRect(find.byKey(const ValueKey('third')));
    expect(third.left, image.left);
    expect(third.top, image.bottom + 12);
    update(() => ratio = 0.75);
    await tester.pump();
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    third = tester.getRect(find.byKey(const ValueKey('third')));
    expect(third.left, second.left);
    expect(third.top, second.bottom + 12);
    expect(tester.takeException(), isNull);
  });
}
