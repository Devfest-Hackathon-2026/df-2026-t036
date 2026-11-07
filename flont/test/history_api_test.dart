import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/drawing_history_screen.dart';
import 'package:illustration_exchange/screens/idea_history_screen.dart';

// サーバー時刻を固定し、実時刻に依存せず期限とページングを検証する。
const serverTime = '2026-11-07T00:00:00Z';
Map<String, dynamic> idea(String id, {int age = 0}) {
  final created = DateTime.parse(serverTime).subtract(Duration(days: age));
  return {
    'ideaId': id,
    'title': id,
    'description': '説明',
    'tags': ['風景'],
    'createdAt': created.toIso8601String(),
    'publishedUntil': created.add(const Duration(days: 7)).toIso8601String(),
    'acceptUntil': created.add(const Duration(days: 30)).toIso8601String(),
    'isOwn': true,
    'hasDrawn': false,
    'canSubmit': false,
  };
}

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response page(List<Map<String, dynamic>> items, {String? cursor}) =>
    response({'items': items, 'nextCursor': cursor, 'serverTime': serverTime});

Widget screen(
  http.Client client, {
  bool drawn = false,
  String base = 'https://api.example.test',
}) => MaterialApp(
  home: drawn
      ? DrawingHistoryScreen(
          apiBaseUrl: base,
          authenticated: true,
          client: client,
          idTokenProvider: () async => 'token',
        )
      : IdeaHistoryScreen(
          apiBaseUrl: base,
          authenticated: true,
          client: client,
          idTokenProvider: () async => 'token',
        ),
);

void main() {
  testWidgets('本人のお題を認証付きで取得し、7日・30日境界を表示する', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/me/ideas');
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.url.queryParameters['limit'], '20');
      return page([idea('公開'), idea('七日', age: 7), idea('三十日', age: 30)]);
    });
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    for (final text in ['公開', '掲載中', 'ピン受付中', '受付終了']) {
      expect(find.text(text), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('追加取得の失敗後も一覧を残し、同じカーソルで再試行する', (tester) async {
    var appendCalls = 0;
    var refresh = false;
    final client = MockClient((request) async {
      if (request.url.queryParameters['cursor'] != null) {
        expect(request.url.queryParameters['cursor'], 'next');
        if (++appendCalls == 1) return response({}, 503);
        return page([idea('二件目')]);
      }
      return refresh
          ? page([idea('更新後')])
          : page([idea('一件目')], cursor: 'next');
    });
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('さらに読み込む'));
    await tester.pumpAndSettle();
    expect(find.text('一件目'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(appendCalls, 2);
    expect(find.text('二件目'), findsOneWidget);
    refresh = true;
    await tester.tap(find.byTooltip('履歴を更新'));
    await tester.pumpAndSettle();
    expect(find.text('更新後'), findsOneWidget);
    expect(find.text('一件目'), findsNothing);
    expect(find.text('二件目'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('参照不可でも送信実績と最終いいねを残し、正常なお題は表示する', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/me/drawn-history');
      return page([
        {
          'submissionId': 'a',
          'ideaId': 'deleted',
          'idea': null,
          'ideaAvailability': 'unavailable',
          'submittedAt': serverTime,
          'lastLiked': true,
        },
        {
          'submissionId': 'b',
          'ideaId': 'normal',
          'idea': idea('正常なお題'),
          'ideaAvailability': 'available',
          'submittedAt': serverTime,
          'lastLiked': false,
        },
      ]);
    });
    await tester.pumpWidget(screen(client, drawn: true));
    await tester.pumpAndSettle();
    expect(find.text('参照できません'), findsOneWidget);
    expect(find.textContaining('いいね済み'), findsOneWidget);
    expect(find.text('正常なお題'), findsOneWidget);
    expect(find.textContaining('いいね未受信'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('本人の詳細から確認後だけ削除し、再取得失敗でもカードを戻さない', (tester) async {
    var deleted = false;
    final client = MockClient((request) async {
      if (request.method == 'DELETE') {
        expect(request.url.path, '/api/v1/ideas/own');
        deleted = true;
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/ideas/own')) return response(idea('own'));
      return deleted ? response({}, 503) : page([idea('own')]);
    });
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('own'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('idea-delete-button')),
    );
    await tester.tap(find.byKey(const ValueKey('idea-delete-button')));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
    await tester.tap(find.byKey(const ValueKey('idea-delete-confirm')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('own'), findsNothing);
    expect(find.text('再試行'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('更新前に開始した追加取得の遅延応答を混ぜない', (tester) async {
    final old = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((request) async {
      if (request.url.queryParameters['cursor'] != null) return old.future;
      return ++calls == 1
          ? page([idea('最初')], cursor: 'next')
          : page([idea('最新')]);
    });
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('さらに読み込む'));
    await tester.pump();
    await tester.tap(find.byTooltip('履歴を更新'));
    await tester.pumpAndSettle();
    old.complete(page([idea('古い応答')]));
    await tester.pumpAndSettle();
    expect(find.text('最新'), findsOneWidget);
    expect(find.text('古い応答'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('空の履歴と未ログインを区別する', (tester) async {
    final client = MockClient((_) async => page([]));
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(find.text('まだアイデア履歴はありません。'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: DrawingHistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('履歴を表示するにはログインしてください。'), findsOneWidget);
    client.close();
  });
}
