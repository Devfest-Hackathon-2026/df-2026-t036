import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/models/received_artwork.dart';
import 'package:illustration_exchange/screens/artwork_detail_screen.dart';
import 'package:illustration_exchange/widgets/artwork_opening_route.dart';

final bytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwLd3wHwAElwJa3P4zawAAAABJRU5ErkJggg==',
);

Widget host({
  required GlobalKey<NavigatorState> navigator,
  required Future<Uint8List> Function() loader,
  required Future<DateTime> Function() markRead,
  bool reduceMotion = false,
  Rect sourceRect = const Rect.fromLTWH(280, 180, 240, 320),
}) => MaterialApp(
  navigatorKey: navigator,
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            ArtworkOpeningRoute(
              sourceRect: sourceRect,
              title: 'Sample',
              label: 'Artwork 1',
              isUnread: true,
              reduceMotion: reduceMotion,
              builder: (_) => ArtworkDetailScreen(
                artwork: const ReceivedArtwork(title: 'Sample'),
                imageLoader: loader,
                onMarkRead: markRead,
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('loads during opening and marks read only after reveal', (
    tester,
  ) async {
    var loads = 0;
    var reads = 0;
    final loading = Completer<Uint8List>();
    await tester.pumpWidget(
      host(
        navigator: GlobalKey<NavigatorState>(),
        loader: () {
          loads++;
          return loading.future;
        },
        markRead: () async {
          reads++;
          return DateTime.now();
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(loads, 1);
    expect(reads, 0);
    loading.complete(bytes);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('opening-letter')), findsOneWidget);
    expect(reads, 0);
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(loads, 1);
    expect(find.byKey(const ValueKey('opening-letter')), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('slow failed image does not hold transition and can retry', (
    tester,
  ) async {
    var loads = 0;
    var reads = 0;
    final loading = Completer<Uint8List>();
    await tester.pumpWidget(
      host(
        navigator: GlobalKey<NavigatorState>(),
        loader: () => ++loads == 1 ? loading.future : Future.value(bytes),
        markRead: () async {
          reads++;
          return DateTime.now();
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 950));
    expect(find.byKey(const ValueKey('opening-letter')), findsNothing);
    expect(reads, 0);
    loading.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('画像を再試行'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back during opening does not mark read', (tester) async {
    var reads = 0;
    final navigator = GlobalKey<NavigatorState>();
    final loading = Completer<Uint8List>();
    await tester.pumpWidget(
      host(
        navigator: navigator,
        loader: () => loading.future,
        markRead: () async {
          reads++;
          return DateTime.now();
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    loading.complete(bytes);
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 640),
    const Size(768, 1024),
    const Size(1280, 720),
  ]) {
    testWidgets('opening fits viewport $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          navigator: GlobalKey<NavigatorState>(),
          sourceRect: Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: 180,
            height: 240,
          ),
          loader: () async => throw StateError('offline'),
          markRead: () async => DateTime.now(),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(ArtworkDetailScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('reduced motion skips envelope animation', (tester) async {
    await tester.pumpWidget(
      host(
        navigator: GlobalKey<NavigatorState>(),
        loader: () async => bytes,
        markRead: () async => DateTime.now(),
        reduceMotion: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('opening-letter')), findsNothing);
    expect(find.byType(ArtworkDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
