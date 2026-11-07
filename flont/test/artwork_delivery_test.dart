import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/artwork_composer_screen.dart';
import 'package:illustration_exchange/screens/idea_detail_screen.dart';
import 'inbox_api_test.dart' as inbox;

void main() {
  testWidgets('受信画像を認証付きで取得し、表示成功後に既読を記録する', (tester) async {
    var marked = false;
    var imageRequests = 0;
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAGCAIAAABxZ0isAAAAFElEQVR4nGMU0bBhwAaYsIrSSQIASVIAhA+B2TgAAAAASUVORK5CYII=',
    );
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.url.path.endsWith('/image')) {
        imageRequests++;
        expect(
          request.url.toString(),
          'https://api.example.test/api/v1/artworks/received/image',
        );
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }
      if (request.url.path.endsWith('/read')) {
        marked = true;
        return http.Response(
          jsonEncode({
            'submissionId': 'received',
            'readAt': DateTime.now().toUtc().toIso8601String(),
          }),
          200,
        );
      }
      return inbox.page('received');
    });
    await tester.pumpWidget(inbox.screen(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('received'));
    // 画像デコードと描画が終わり、既読処理が呼ばれるまで待つ。
    await tester.runAsync(() async {
      for (var i = 0; i < 500 && !marked; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(imageRequests, 1);
    expect(marked, isTrue);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('送信画面から詳細へ戻ると送信済み状態を取得してボタンを消す', (tester) async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        jsonEncode({
          'title': 'お題',
          'description': '説明',
          'tags': [],
          'createdAt': '2026-11-08T00:00:00Z',
          'publishedUntil': '2026-11-15T00:00:00Z',
          'isOwn': false,
          'hasDrawn': requests > 1,
          'canSubmit': requests == 1,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: IdeaDetailScreen(
          idea: IdeaSlotData(
            ideaId: 'idea',
            title: 'お題',
            expiresAt: DateTime(2026, 11, 15),
          ),
          apiBaseUrl: 'https://api.example.test',
          authenticated: true,
          client: client,
          idTokenProvider: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final send = find.byKey(const ValueKey('idea-send-artwork-button'));
    await tester.scrollUntilVisible(send, 200);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();
    final composer = tester.widget<ArtworkComposerScreen>(
      find.byType(ArtworkComposerScreen),
    );
    expect(composer.client, same(client));
    expect(composer.apiBaseUrl, 'https://api.example.test');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(send, findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
}
