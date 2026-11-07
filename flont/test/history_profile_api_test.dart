import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/idea_history_screen.dart';
import 'package:illustration_exchange/screens/drawing_history_screen.dart';
import 'package:illustration_exchange/screens/idea_detail_screen.dart';
import 'package:illustration_exchange/screens/profile_screen.dart';
import 'package:illustration_exchange/widgets/profile_card.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> idea(String id, {int days = 1}) {
  final date = DateTime.utc(2026, 11, 7).subtract(Duration(days: days));
  return {
    'ideaId': id,
    'title': id,
    'description': 'Description',
    'tags': ['tag'],
    'createdAt': date.toIso8601String(),
    'publishedUntil': date.add(const Duration(days: 7)).toIso8601String(),
    'acceptUntil': date.add(const Duration(days: 30)).toIso8601String(),
    'isOwn': true,
    'canSubmit': false,
    'hasDrawn': false,
  };
}

Map<String, dynamic> page(List<Object> items, {String? cursor}) => {
  'items': items,
  'nextCursor': cursor,
  'serverTime': '2026-11-07T00:00:00Z',
};
Map<String, dynamic> me(int count) => {
  'uid': 'me',
  'nickname': 'User-$count',
  'status': 'active',
  'ideaCount': count,
  'drawnCount': count + 1,
  'likesReceived': count + 2,
};
Widget own(http.Client client) => MaterialApp(
  home: IdeaHistoryScreen(
    authenticated: true,
    client: client,
    idTokenProvider: () async => 'token',
  ),
);
Widget profile(http.Client client, {bool active = true}) => MaterialApp(
  home: Scaffold(
    body: ProfileScreen(
      me: initialMe,
      active: active,
      client: client,
      idTokenProvider: () async => 'token',
    ),
  ),
);
final initialMe = me(0);

void main() {
  group('history and profile APIs', () {
    testWidgets(
      'own history shows server-based states and isolates malformed cards',
      (tester) async {
        final client = MockClient((request) async {
          expect(request.url.path, '/api/v1/me/ideas');
          expect(request.headers['Authorization'], 'Bearer token');
          return response(
            page([
              idea('Published'),
              idea('Pinned', days: 10),
              idea('Closed', days: 35),
              {'ideaId': 'broken'},
            ]),
          );
        });
        await tester.pumpWidget(own(client));
        await tester.pumpAndSettle();
        expect(find.text('掲載中'), findsOneWidget);
        expect(find.text('ピン受付中'), findsOneWidget);
        expect(find.text('受付終了'), findsOneWidget);
        expect(find.text('この履歴を読み込めませんでした。'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
    testWidgets(
      'history deletion updates list after confirmed detail deletion',
      (tester) async {
        var deleted = false;
        final client = MockClient((request) async {
          if (request.method == 'DELETE') {
            deleted = true;
            return http.Response('', 204);
          }
          if (request.url.path.endsWith('/me/ideas')) {
            return response(page(deleted ? [] : [idea('Own')]));
          }
          return response(idea('Own'));
        });
        await tester.pumpWidget(own(client));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Own'));
        await tester.pumpAndSettle();
        expect(find.byType(IdeaDetailScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('idea-delete-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('idea-delete-confirm')));
        await tester.pumpAndSettle();
        expect(deleted, isTrue);
        expect(find.text('Own'), findsNothing);
        expect(find.text('まだ履歴はありません'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
    testWidgets(
      'drawing history keeps unavailable entries and final likes without images',
      (tester) async {
        final client = MockClient(
          (request) async => response(
            page([
              {
                'submissionId': 'a',
                'ideaId': 'drawn',
                'submittedAt': '2026-11-06T00:00:00Z',
                'lastLiked': true,
                'ideaAvailability': 'available',
                'idea': idea('drawn'),
              },
              {
                'submissionId': 'b',
                'ideaId': 'missing',
                'submittedAt': '2026-11-05T00:00:00Z',
                'lastLiked': false,
                'ideaAvailability': 'unavailable',
                'idea': null,
              },
            ]),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: DrawingHistoryScreen(
              authenticated: true,
              client: client,
              idTokenProvider: () async => 'token',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('drawn'), findsOneWidget);
        expect(find.text('参照できません'), findsOneWidget);
        expect(find.textContaining('いいね済み'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(find.byKey(const ValueKey('idea-delete-button')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
    testWidgets(
      'failed additional page retains history and retries same cursor',
      (tester) async {
        var attempts = 0;
        final client = MockClient((request) async {
          if (!request.url.queryParameters.containsKey('cursor')) {
            return response(page([idea('First')], cursor: 'next'));
          }
          expect(request.url.queryParameters['cursor'], 'next');
          if (++attempts == 1) {
            return response({
              'error': {'message': 'temporary'},
            }, 503);
          }
          return response(page([idea('Second')]));
        });
        await tester.pumpWidget(own(client));
        await tester.pumpAndSettle();
        await tester.tap(find.text('さらに読み込む'));
        await tester.pumpAndSettle();
        expect(find.text('First'), findsOneWidget);
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();
        expect(find.text('First'), findsOneWidget);
        expect(find.text('Second'), findsOneWidget);
        expect(attempts, 2);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
    testWidgets('returning to profile refreshes all counters from server', (
      tester,
    ) async {
      var requests = 0;
      final client = MockClient((request) async => response(me(++requests)));
      await tester.pumpWidget(profile(client));
      await tester.pumpAndSettle();
      expect(tester.widget<ProfileCard>(find.byType(ProfileCard)).ideaCount, 1);
      await tester.pumpWidget(profile(client, active: false));
      await tester.pumpAndSettle();
      expect(requests, 1);
      await tester.pumpWidget(profile(client));
      await tester.pumpAndSettle();
      final card = tester.widget<ProfileCard>(find.byType(ProfileCard));
      expect([card.ideaCount, card.drawingCount, card.likeCount], [2, 3, 4]);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
    testWidgets('returning from history refreshes profile', (tester) async {
      var requests = 0;
      final client = MockClient(
        (request) async => request.url.path.endsWith('/me')
            ? response(me(++requests))
            : response(page([])),
      );
      await tester.pumpWidget(profile(client));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('アイデア履歴'), 200);
      await tester.tap(find.text('アイデア履歴'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(tester.widget<ProfileCard>(find.byType(ProfileCard)).ideaCount, 2);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
    testWidgets(
      'failed profile refresh retains existing information and supports retry',
      (tester) async {
        var requests = 0;
        final client = MockClient(
          (request) async => ++requests == 1
              ? response({
                  'error': {'message': 'temporary'},
                }, 503)
              : response(me(5)),
        );
        await tester.pumpWidget(profile(client));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ProfileCard>(find.byType(ProfileCard)).ideaCount,
          0,
        );
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ProfileCard>(find.byType(ProfileCard)).ideaCount,
          5,
        );
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
    testWidgets('stale profile responses cannot overwrite refreshed counters', (
      tester,
    ) async {
      final old = Completer<http.Response>();
      var requests = 0;
      final client = MockClient(
        (request) async => ++requests == 1 ? old.future : response(me(9)),
      );
      await tester.pumpWidget(profile(client));
      await tester.pump();
      await tester.pumpWidget(profile(client, active: false));
      await tester.pumpWidget(profile(client));
      await tester.pumpAndSettle();
      old.complete(response(me(1)));
      await tester.pumpAndSettle();
      expect(tester.widget<ProfileCard>(find.byType(ProfileCard)).ideaCount, 9);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
  }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
}
