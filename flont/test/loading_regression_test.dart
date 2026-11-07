import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/ideas_screen.dart';
import 'package:illustration_exchange/screens/timeline_screen.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> idea(String id) => {
  'ideaId': id,
  'title': id,
  'tags': <String>[],
  'createdAt': '2026-11-07T00:00:00Z',
  'publishedUntil': '2026-11-14T00:00:00Z',
  'canPin': true,
};

void main() {
  testWidgets('one failed slot does not hide healthy slots or become empty', (
    tester,
  ) async {
    var fail = true;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/me/slots')) {
        return response({
          'slots': {
            'slot_0': {'ideaId': 'healthy'},
            'slot_1': {'ideaId': 'unavailable'},
          },
        });
      }
      final id = request.url.pathSegments.last;
      if (id == 'unavailable' && fail) return response({}, 404);
      return response(idea(id));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeasScreen(
            authenticated: true,
            client: client,
            idTokenProvider: () async => 'token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('healthy'), findsOneWidget);
    final failed = find.byKey(const ValueKey('idea-slot-2'));
    expect(
      find.descendant(
        of: failed,
        matching: find.byIcon(Icons.add_circle_outline),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: failed, matching: find.byType(TextButton)),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(
      find.descendant(of: failed, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text('healthy'), findsOneWidget);
    expect(find.text('unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  }, skip: const bool.fromEnvironment('DEV_PREVIEW'));

  for (final oldFails in [false, true]) {
    testWidgets('ignore stale timeline completion (failure: $oldFails)', (
      tester,
    ) async {
      final old = Completer<http.Response>();
      final fresh = Completer<http.Response>();
      var requests = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/me/pins')) {
          return response({'items': []});
        }
        return ++requests == 1 ? old.future : fresh.future;
      });
      Widget build(bool active) => MaterialApp(
        home: Scaffold(
          body: TimelineScreen(
            authenticated: true,
            active: active,
            client: client,
            idTokenProvider: () async => 'token',
          ),
        ),
      );
      await tester.pumpWidget(build(true));
      await tester.pump();
      await tester.pumpWidget(build(false));
      await tester.pumpWidget(build(true));
      await tester.pump();
      expect(requests, 2);
      if (oldFails) {
        old.completeError(StateError('stale-error'));
      } else {
        old.complete(
          response({
            'items': [idea('stale')],
            'nextCursor': null,
          }),
        );
      }
      await tester.pump();
      await tester.pump();
      expect(find.text('stale'), findsNothing);
      expect(find.text('stale-error'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      fresh.complete(
        response({
          'items': [idea('fresh')],
          'nextCursor': null,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('fresh'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
  }
}
