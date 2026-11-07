import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/models/received_artwork.dart';
import 'package:illustration_exchange/screens/artwork_detail_screen.dart';

final imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwLd3wHwAElwJa3P4zawAAAABJRU5ErkJggg==',
);
Widget detail({
  required Future<Uint8List> Function() loader,
  required Future<DateTime> Function() markRead,
  DateTime? expiry,
  DateTime Function()? now,
}) => MaterialApp(
  home: ArtworkDetailScreen(
    artwork: ReceivedArtwork(title: 'Sample', expiresAt: expiry),
    imageLoader: loader,
    onMarkRead: markRead,
    now: now,
  ),
);
Future<void> decodeImage(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mark read only after decoded image is displayed', (
    tester,
  ) async {
    final loading = Completer<Uint8List>();
    var reads = 0;
    await tester.pumpWidget(
      detail(
        loader: () => loading.future,
        markRead: () async {
          reads++;
          return DateTime.now();
        },
      ),
    );
    await tester.pump();
    expect(reads, 0);
    loading.complete(imageBytes);
    await decodeImage(tester);
    expect(find.byType(Image), findsOneWidget);
    expect(reads, 1);
    await tester.pump();
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('image load failure stays unread and retry can succeed', (
    tester,
  ) async {
    var attempts = 0;
    var reads = 0;
    await tester.pumpWidget(
      detail(
        loader: () async {
          if (++attempts == 1) throw StateError('offline');
          return imageBytes;
        },
        markRead: () async {
          reads++;
          return DateTime.now();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.tap(find.text('画像を再試行'));
    await decodeImage(tester);
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('invalid image bytes never mark read', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      detail(
        loader: () async => Uint8List.fromList([1, 2, 3]),
        markRead: () async {
          reads++;
          return DateTime.now();
        },
      ),
    );
    await decodeImage(tester);
    expect(reads, 0);
    expect(find.text('画像を再試行'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('read failure retries without reloading the image', (
    tester,
  ) async {
    var loads = 0;
    var reads = 0;
    await tester.pumpWidget(
      detail(
        loader: () async {
          loads++;
          return imageBytes;
        },
        markRead: () async {
          if (++reads == 1) throw StateError('offline');
          return DateTime.now();
        },
      ),
    );
    await decodeImage(tester);
    await tester.scrollUntilVisible(find.text('既読を再試行'), 200);
    await tester.tap(find.text('既読を再試行'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(loads, 1);
    expect(find.text('既読を再試行'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('expiry removes image while detail remains open', (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    await tester.pumpWidget(
      detail(
        loader: () async => imageBytes,
        markRead: () async => now,
        expiry: now.add(const Duration(seconds: 5)),
        now: () => now,
      ),
    );
    await decodeImage(tester);
    expect(find.byType(Image), findsOneWidget);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(Image), findsNothing);
    expect(find.text('閲覧期限切れ'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
