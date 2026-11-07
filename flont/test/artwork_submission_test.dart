import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/artwork_composer_screen.dart';
import 'artwork_composer_screen_test.dart' show samplePng;

const sendKey = ValueKey('artwork-send');
const confirmKey = ValueKey('artwork-confirm');
http.StreamedResponse result(int status, Object data) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(data))), status);
const completed = {
  'submissionId': 'saved-artwork',
  'submittedAt': '2026-11-08T00:00:00Z',
};

Future<void> openComposer(
  WidgetTester tester,
  http.Client client, {
  Future<String?> Function()? token,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final png = await tester.runAsync(samplePng);
  await tester.pumpWidget(
    MaterialApp(
      home: ArtworkComposerScreen(
        ideaId: '00000000-0000-4000-8000-000000000000',
        ideaTitle: '夜明けの庭',
        ideaCreatedAt: DateTime(2026, 11, 8),
        apiBaseUrl: 'https://api.example.test/',
        client: client,
        idTokenProvider: token ?? () async => 'token',
        pickImage: () async =>
            XFile.fromData(png!, name: 'image.png', path: 'image.png'),
      ),
    ),
  );
  // 実際の画像変換が終わり、送信操作が可能になるまで待つ。
  await tester.runAsync(() async {
    await tester.tap(find.text('イラストを選択'));
    for (var index = 0; index < 500; index++) {
      await tester.pump();
      if (tester.widget<FilledButton>(find.byKey(sendKey)).onPressed != null) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('画像変換が完了しませんでした');
  });
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(sendKey));
  await tester.tap(find.byKey(sendKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(confirmKey));
  await tester.pump();
}

void main() {
  testWidgets('確認後だけ正しい接続先と認証・変換済み画像を送信する', (tester) async {
    var requests = 0;
    final client = MockClient.streaming((request, stream) async {
      requests++;
      expect(
        request.url.toString(),
        'https://api.example.test/api/v1/artworks',
      );
      expect(request.headers['Authorization'], 'Bearer token');
      final multipart = request as http.MultipartRequest;
      expect(
        multipart.fields['ideaId'],
        '00000000-0000-4000-8000-000000000000',
      );
      expect(multipart.files.single.filename, 'image.png');
      expect(await stream.toBytes(), isNotEmpty);
      return result(201, completed);
    });
    await openComposer(tester, client);
    expect(requests, 0);
    await tester.tap(find.byKey(sendKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('送信完了'), findsWidgets);
    expect(find.text('イラストを送信しました。描いた履歴から確認できます。'), findsOneWidget);
    client.close();
  });

  testWidgets('一時障害後は画像を変えず再試行し200の確定結果を受け取る', (tester) async {
    final uploads = <String>[];
    final client = MockClient.streaming((request, stream) async {
      final body = latin1.decode(await stream.toBytes());
      uploads.add(body.split('\r\n\r\n').last.split('\r\n--').first);
      return uploads.length == 1
          ? result(503, {
              'error': {'message': '再試行してください。'},
            })
          : result(200, completed);
    });
    await openComposer(tester, client);
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('artwork-reselect')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('同じ画像で再試行'));
    await tester.pumpAndSettle();
    expect(uploads, hasLength(2));
    expect(uploads[0], uploads[1]);
    expect(find.text('送信完了'), findsWidgets);
    client.close();
  });

  testWidgets('審査拒否は完了にせず、画像の選び直しを許可する', (tester) async {
    final client = MockClient.streaming((request, stream) async {
      await stream.drain<void>();
      return result(422, {
        'error': {'code': 'IMAGE_REJECTED', 'message': 'この画像は送信できません。'},
      });
    });
    await openComposer(tester, client);
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(find.text('この画像は送信できません。'), findsOneWidget);
    expect(find.text('送信完了'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('artwork-reselect')))
          .onPressed,
      isNotNull,
    );
    client.close();
  });

  testWidgets('送信中の再送信を止め、認証が遅れてもタイムアウト後は送信しない', (tester) async {
    final token = Completer<String?>();
    var requests = 0;
    final client = MockClient.streaming((request, stream) async {
      requests++;
      await stream.drain<void>();
      return result(201, completed);
    });
    await openComposer(tester, client, token: () => token.future);
    await confirm(tester);
    expect(tester.widget<FilledButton>(find.byKey(sendKey)).onPressed, isNull);
    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();
    token.complete('late-token');
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('同じ画像で再試行'), findsOneWidget);
    client.close();
  });
}
