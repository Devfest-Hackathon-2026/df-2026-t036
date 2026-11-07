import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/profile_screen.dart';
import 'package:illustration_exchange/widgets/profile_card.dart';

// 累計は画面側で加減算せず、APIが返した値で置き換わることを確認する。
Map<String, dynamic> me(int count, {String uid = 'artist'}) => {
  'uid': uid,
  'nickname': '名前-$uid',
  'status': 'active',
  'ideaCount': count,
  'drawnCount': count + 1,
  'likesReceived': count + 2,
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Widget screen(
  http.Client client, {
  bool active = true,
  String uid = 'artist',
}) => MaterialApp(
  home: Scaffold(
    body: ProfileScreen(
      me: me(1, uid: uid),
      active: active,
      apiBaseUrl: 'https://api.example.test',
      client: client,
      idTokenProvider: () async => 'token',
    ),
  ),
);
ProfileCard card(WidgetTester tester) =>
    tester.widget<ProfileCard>(find.byType(ProfileCard));

void main() {
  testWidgets('表示時とタブ復帰時に認証付きで三つの累計を更新する', (tester) async {
    var count = 4;
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.toString(), 'https://api.example.test/api/v1/me');
      expect(request.headers['Authorization'], 'Bearer token');
      return response(me(count));
    });
    await tester.pumpWidget(screen(client, active: false));
    await tester.pumpAndSettle();
    expect(requests, 0);
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(card(tester).ideaCount, 4);
    expect(card(tester).drawingCount, 5);
    expect(card(tester).likeCount, 6);
    await tester.pumpWidget(screen(client, active: false));
    count = 2;
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(card(tester).ideaCount, 2);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('更新失敗時は直前の累計を維持し再試行で更新する', (tester) async {
    var fail = false;
    final client = MockClient(
      (_) async => fail ? response({}, 503) : response(me(7)),
    );
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    fail = true;
    // 手動更新ボタンを使わず、タブ復帰による再取得を確認する。
    await tester.pumpWidget(screen(client, active: false));
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(card(tester).ideaCount, 7);
    expect(find.text('再試行'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(find.text('再試行'), findsNothing);
    expect(card(tester).likeCount, 9);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('履歴から戻ると削除等で変わった累計を再取得する', (tester) async {
    var count = 5;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/me/ideas')) {
        return response({
          'items': [],
          'nextCursor': null,
          'serverTime': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return response(me(count));
    });
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    // 画面下部の履歴メニューはスクロールしてから生成・操作する。
    await tester.scrollUntilVisible(find.text('アイデア履歴'), 200);
    await tester.tap(find.text('アイデア履歴'));
    await tester.pumpAndSettle();
    count = 3;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(card(tester).ideaCount, 3);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('ユーザー切替前の遅延応答で他人の累計を表示しない', (tester) async {
    final old = Completer<http.Response>();
    var calls = 0;
    final client = MockClient(
      (_) async => ++calls == 1 ? old.future : response(me(9, uid: 'other')),
    );
    await tester.pumpWidget(screen(client));
    await tester.pump();
    await tester.pumpWidget(screen(client, uid: 'other'));
    await tester.pumpAndSettle();
    old.complete(response(me(99)));
    await tester.pumpAndSettle();
    expect(card(tester).nickname, '名前-other');
    expect(card(tester).ideaCount, 9);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('背景から復帰したときに新しいいいね累計を取得する', (tester) async {
    var count = 1;
    final client = MockClient((_) async => response(me(count)));
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    count = 8;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(card(tester).likeCount, 10);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
}
