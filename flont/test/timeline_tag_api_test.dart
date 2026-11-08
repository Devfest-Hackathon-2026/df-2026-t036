import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/timeline_screen.dart';

void main() {
  testWidgets('タグ選択で先頭へ戻り、解除時は古い通信結果を無視する', (tester) async {
    final requests = <Uri>[];
    final delayed = Completer<http.Response>();
    var allRequests = 0;
    http.Response page(String title, {String? cursor}) => http.Response(
      jsonEncode({
        'tags': ['風景', '海'],
        'items': [
          {
            'ideaId': title,
            'title': title,
            'tags': <String>[],
            'createdAt': '2026-11-07T00:00:00Z',
            'canPin': true,
          },
        ],
        'nextCursor': cursor,
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/me/pins')) {
        return http.Response('{"items":[]}', 200);
      }
      requests.add(request.url);
      if (request.url.queryParameters['tag'] == '風景') return delayed.future;
      allRequests++;
      return page('全体$allRequests', cursor: 'next');
    });
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
    expect(find.byKey(const ValueKey('timeline-tag-海')), findsOneWidget);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['cursor'], 'next');
    await tester.tap(find.byKey(const ValueKey('timeline-tag-風景')));
    await tester.pump();
    expect(requests.last.queryParameters['tag'], '風景');
    expect(requests.last.queryParameters.containsKey('cursor'), isFalse);
    // 読み込み中に選択解除しても、先行する応答で表示を上書きしない。
    await tester.tap(find.byKey(const ValueKey('timeline-tag-all')));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters.containsKey('tag'), isFalse);
    expect(requests.last.queryParameters.containsKey('cursor'), isFalse);
    delayed.complete(page('古い絞り込み結果'));
    await tester.pumpAndSettle();
    expect(find.text('全体3'), findsOneWidget);
    expect(find.text('古い絞り込み結果'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
}
