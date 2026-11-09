import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/inbox_screen.dart';
import 'package:illustration_exchange/screens/artwork_detail_screen.dart';

http.Response page(String title, {String? cursor}) => http.Response(
  jsonEncode({
    'items': [
      {
        'submissionId': title,
        'artistId': 'artist',
        'artistNickname': 'Artist',
        'artistProfileAvailable': true,
        'sourceIdeaId': 'deleted-idea',
        'sourceIdeaSnapshot': {
          'title': title,
          'description': 'Snapshot description',
          'tags': ['tag'],
          'ownerId': 'owner',
        },
        'liked': false,
        'readAt': null,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String(),
      },
    ],
    'nextCursor': cursor,
    'serverTime': DateTime.now().toUtc().toIso8601String(),
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget screen(http.Client client, {bool active = true, String? userId}) =>
    MaterialApp(
      home: Scaffold(
        body: InboxScreen(
          authenticated: true,
          userId: userId,
          active: active,
          apiBaseUrl: 'https://api.example.test/',
          client: client,
          idTokenProvider: () async => 'test-token',
        ),
      ),
    );

void main() {
  group('inbox API', () {
    testWidgets('画像取得失敗でもスナップショットを表示し既読にしない', (tester) async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.url.path.endsWith('/image')) return http.Response('', 404);
        expect(request.url.queryParameters['limit'], '20');
        return page('Received idea');
      });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Received idea'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkDetailScreen), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Artist'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Snapshot description'), 200);
      expect(find.text('Snapshot description'), findsOneWidget);
      expect(find.text('tag'), findsOneWidget);
      expect(paths, hasLength(2));
      expect(paths.first, '/api/v1/me/artworks/inbox');
      expect(paths.last, endsWith('/image'));
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('double tap opens one detail and fetches the image once', (
      tester,
    ) async {
      var images = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/image')) {
          images++;
          return http.Response('', 404);
        }
        return page('Received idea');
      });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      final position = tester.getCenter(find.text('Received idea'));
      await tester.tapAt(position);
      await tester.tapAt(position);
      await tester.pumpAndSettle();
      expect(images, 1);
      expect(find.byType(ArtworkDetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkDetailScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('reopening reuses image, account change and disposal refetch', (
      tester,
    ) async {
      var images = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/image')) {
          images++;
          return http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwLd3wHwAElwJa3P4zawAAAABJRU5ErkJggg==',
            ),
            200,
          );
        }
        if (request.url.path.endsWith('/read')) {
          return http.Response(
            jsonEncode({
              'submissionId': 'Received idea',
              'readAt': DateTime.now().toUtc().toIso8601String(),
            }),
            200,
          );
        }
        return page('Received idea');
      });
      Future<void> open() async {
        await tester.tap(find.text('Received idea'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
      }

      Future<void> back() async {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(screen(client, userId: 'one'));
      await tester.pumpAndSettle();
      await open();
      await back();
      await open();
      expect(images, 1);
      await back();
      await tester.pumpWidget(screen(client, userId: 'two'));
      await tester.pumpAndSettle();
      await open();
      expect(images, 2);
      await back();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(client, userId: 'two'));
      await tester.pumpAndSettle();
      await open();
      expect(images, 3);
      await back();
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('successful refresh removes images no longer in the inbox', (
      tester,
    ) async {
      var removed = false;
      var images = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/image')) {
          images++;
          return http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwLd3wHwAElwJa3P4zawAAAABJRU5ErkJggg==',
            ),
            200,
          );
        }
        if (request.url.path.endsWith('/read')) {
          return http.Response(
            jsonEncode({
              'submissionId': 'Received idea',
              'readAt': DateTime.now().toUtc().toIso8601String(),
            }),
            200,
          );
        }
        if (removed) {
          return http.Response(
            jsonEncode({
              'items': [],
              'nextCursor': null,
              'serverTime': DateTime.now().toUtc().toIso8601String(),
            }),
            200,
          );
        }
        return page('Received idea');
      });
      Future<void> open() async {
        await tester.tap(find.text('Received idea'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      await open();
      removed = true;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Received idea'), findsNothing);
      removed = false;
      await tester.pumpWidget(screen(client, active: false));
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      await open();
      expect(images, 2);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('invalid cached image is discarded and retry refetches', (
      tester,
    ) async {
      var images = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/image')) {
          images++;
          return http.Response.bytes(
            images == 1
                ? [1, 2, 3]
                : base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwLd3wHwAElwJa3P4zawAAAABJRU5ErkJggg==',
                  ),
            200,
          );
        }
        if (request.url.path.endsWith('/read')) {
          return http.Response(
            jsonEncode({
              'submissionId': 'Received idea',
              'readAt': DateTime.now().toUtc().toIso8601String(),
            }),
            200,
          );
        }
        return page('Received idea');
      });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Received idea'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('画像を再試行'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(images, 2);
      expect(find.text('画像を再試行'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('pagination uses cursor and refresh discards old pages', (
      tester,
    ) async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (requests == 1) return page('First', cursor: 'next');
        if (requests == 2) {
          expect(request.url.queryParameters['cursor'], 'next');
          return page('Second');
        }
        expect(request.url.queryParameters.containsKey('cursor'), isFalse);
        return page('Fresh');
      });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('さらに読み込む'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('次の作品'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      // 更新ボタンの代わりに、受信箱へ戻った際の自動再取得を検証する。
      await tester.pumpWidget(screen(client, active: false));
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Second'), findsNothing);
      expect(find.byTooltip('次の作品'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('failed refresh preserves existing cards and can retry', (
      tester,
    ) async {
      var requests = 0;
      final client = MockClient((request) async {
        if (++requests == 2) {
          return http.Response('{"error":{"message":"temporary-error"}}', 503);
        }
        return page(requests == 1 ? 'Existing' : 'Recovered');
      });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      // 更新ボタンの代わりに、受信箱へ戻った際の自動再取得を検証する。
      await tester.pumpWidget(screen(client, active: false));
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      expect(find.text('Existing'), findsOneWidget);
      expect(find.text('temporary-error'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(find.text('Recovered'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('returning to inbox ignores a stale response', (tester) async {
      final old = Completer<http.Response>();
      var requests = 0;
      final client = MockClient(
        (request) async => ++requests == 1 ? old.future : page('Fresh'),
      );
      await tester.pumpWidget(screen(client));
      await tester.pump();
      await tester.pumpWidget(screen(client, active: false));
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      old.complete(page('Stale'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Stale'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets('auto refresh runs only while active', (tester) async {
      var requests = 0;
      final client = MockClient(
        (request) async => page('Version-${++requests}'),
      );
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 180));
      await tester.pumpAndSettle();
      expect(requests, 2);
      await tester.pumpWidget(screen(client, active: false));
      await tester.pump(const Duration(seconds: 360));
      expect(requests, 2);
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      expect(requests, 3);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
  }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
}
