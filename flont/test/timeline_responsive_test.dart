import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/timeline_screen.dart';
import 'package:illustration_exchange/widgets/idea_card.dart';

void main() {
  for (final spec in [(390.0, 1), (768.0, 2), (1280.0, 3)]) {
    testWidgets('timeline uses ${spec.$2} columns at width ${spec.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(spec.$1, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/me/pins')
                ? {'items': []}
                : {
                    'items': List.generate(
                      6,
                      (index) => {
                        'ideaId': 'idea-$index',
                        'title': 'Idea $index',
                        'tags': ['tag'],
                        'createdAt': '2026-11-07T00:00:00Z',
                        'canPin': true,
                      },
                    ),
                    'nextCursor': null,
                  },
          ),
          200,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineScreen(
              authenticated: true,
              client: client,
              idTokenProvider: () async => 'token',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.byKey(const ValueKey('idea-0')));
      final nextRow = tester.getRect(find.byKey(ValueKey('idea-${spec.$2}')));
      expect(nextRow.top, greaterThan(first.bottom));
      if (spec.$2 > 1) {
        final second = tester.getRect(find.byKey(const ValueKey('idea-1')));
        expect(second.top, closeTo(first.top, 0.01));
        expect(second.left, greaterThan(first.right));
      }
      expect(
        tester.getSize(find.byType(IdeaCard).first).width,
        lessThanOrEqualTo(spec.$1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.close();
    }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
  }
}
