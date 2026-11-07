import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/timeline_screen.dart';

void main() {
  // 戻った画面で他タブの変更が反映されるよう、再取得されることを確認する。
  testWidgets('タイムラインへ戻ると再取得する', (tester) async {
    var requests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/me/pins')) {
        return http.Response('{"items":[]}', 200);
      }
      requests++;
      return http.Response(
        jsonEncode({
          'items': [
            {
              'ideaId': 'idea',
              'title': 'version-$requests',
              'tags': <String>[],
              'createdAt': '2026-11-07T00:00:00Z',
              'canPin': true,
            },
          ],
          'nextCursor': null,
        }),
        200,
      );
    });
    Widget build(bool active) => MaterialApp(
      home: Scaffold(
        body: TimelineScreen(
          active: active,
          authenticated: true,
          client: client,
          idTokenProvider: () async => 'test-token',
        ),
      ),
    );
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(find.text('version-1'), findsOneWidget);
    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(requests, 1);
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(find.text('version-2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
  // 二ページ目の失敗後、再試行が一ページ目へ戻らず同じカーソルを使う。
  testWidgets('失敗したページのカーソルで再試行する', (tester) async {
    var secondPageRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/me/pins')) {
        return http.Response(jsonEncode({'items': []}), 200);
      }
      final secondPage = request.url.queryParameters['cursor'] == 'page-2';
      if (secondPage && ++secondPageRequests == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': '一時的な失敗'},
          }),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({
          'items': [
            {
              'ideaId': secondPage ? 'second' : 'first',
              'title': secondPage ? '二ページ目のお題' : '一ページ目のお題',
              'tags': <String>[],
              'createdAt': '2026-11-07T00:00:00Z',
              'canPin': true,
            },
          ],
          'nextCursor': secondPage ? null : 'page-2',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineScreen(
            authenticated: true,
            client: client,
            idTokenProvider: () async => 'test-token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('一時的な失敗'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(secondPageRequests, 2);
    expect(find.text('二ページ目のお題'), findsOneWidget);
    expect(find.text('一ページ目のお題'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  }, skip: const bool.fromEnvironment('DEV_PREVIEW'));
}
