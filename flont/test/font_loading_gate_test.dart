import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/widgets/font_loading_gate.dart';

void main() {
  testWidgets('waits for fonts before displaying the app', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: FontLoadingGate(
          loadFonts: () => ready.future,
          child: const Text('Ready'),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    expect(find.byType(Text), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('can retry a failed font load', (tester) async {
    final ready = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FontLoadingGate(
          loadFonts: () {
            attempts++;
            return attempts == 1
                ? Future.error(StateError('offline'))
                : ready.future;
          },
          child: const Text('Ready'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsNothing);
    await tester.tap(find.text('再試行'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('can continue when fonts are unavailable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FontLoadingGate(
          loadFonts: () => Future.error(StateError('offline')),
          child: const Text('Ready'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('そのまま続ける'));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
  });
  testWidgets('prepares the page behind the bar and preserves its state', (
    tester,
  ) async {
    final fonts = Completer<void>();
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FontLoadingGate(
          loadFonts: () => fonts.future,
          child: StatefulBuilder(
            builder: (context, setState) {
              builds++;
              return const Text('Prepared');
            },
          ),
        ),
      ),
    );
    expect(builds, 0);
    await tester.pump();
    expect(builds, greaterThan(0));
    expect(find.text('Prepared'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final preparedState = tester.state(
      find.byType(StatefulBuilder, skipOffstage: false),
    );
    fonts.complete();
    await tester.pumpAndSettle();
    expect(find.text('Prepared'), findsOneWidget);
    expect(tester.state(find.byType(StatefulBuilder)), same(preparedState));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
