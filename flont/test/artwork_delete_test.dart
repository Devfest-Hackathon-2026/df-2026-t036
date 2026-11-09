import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/models/received_artwork.dart';
import 'package:illustration_exchange/screens/artwork_detail_screen.dart';

Widget app(
  Future<void> Function() delete, {
  ValueChanged<bool?>? result,
  DateTime? expiry,
  DateTime Function()? now,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final deleted = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => ArtworkDetailScreen(
                artwork: ReceivedArtwork(
                  title: 'Received artwork',
                  expiresAt: expiry,
                ),
                onDelete: delete,
                now: now,
              ),
            ),
          );
          result?.call(deleted);
        },
        child: const Text('Open'),
      ),
    ),
  ),
);
Future<void> openDelete(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('artwork-delete-button')),
    300,
  );
  await tester.tap(find.byKey(const ValueKey('artwork-delete-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cancel leaves received artwork intact; confirming deletes and returns',
    (tester) async {
      var calls = 0;
      bool? result;
      await tester.pumpWidget(
        app(() async {
          calls++;
        }, result: (value) => result = value),
      );
      await openDelete(tester);
      expect(calls, 0);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(ArtworkDetailScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('artwork-delete-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('artwork-delete-confirm')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(result, isTrue);
      expect(find.byType(ArtworkDetailScreen), findsNothing);
    },
  );
  testWidgets(
    'pending delete prevents duplicate submission and leaving detail',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        app(() {
          calls++;
          return pending.future;
        }),
      );
      await openDelete(tester);
      await tester.tap(find.byKey(const ValueKey('artwork-delete-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('artwork-delete-button')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkDetailScreen), findsNothing);
      expect(calls, 1);
    },
  );
  testWidgets('failed delete keeps detail and can be retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(() async {
        if (++calls == 1) throw StateError('offline');
      }),
    );
    await openDelete(tester);
    await tester.tap(find.byKey(const ValueKey('artwork-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkDetailScreen), findsOneWidget);
    expect(find.text('作品を削除できませんでした。再度お試しください。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artwork-delete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('artwork-delete-confirm')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(ArtworkDetailScreen), findsNothing);
  });
  testWidgets('expiry during confirmation does not send a deletion', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 7);
    var calls = 0;
    await tester.pumpWidget(
      app(
        () async {
          calls++;
        },
        expiry: now.add(const Duration(seconds: 5)),
        now: () => now,
      ),
    );
    await openDelete(tester);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('artwork-delete-confirm')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(ArtworkDetailScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
