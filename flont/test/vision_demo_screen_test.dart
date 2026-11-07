import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illustration_exchange/screens/vision_demo_screen.dart';

// 小さなPNGを使い、画像プレビューも実際に描画する。
XFile image([String name = 'sample.png']) {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAGCAIAAABxZ0isAAAAFElEQVR4nGMU0bBhwAaYsIrSSQIASVIAhA+B2TgAAAAASUVORK5CYII=',
  );
  return XFile.fromData(bytes, name: name, path: name);
}

Widget screen(Future<XFile?> Function() picker, {http.Client? client}) =>
    MaterialApp(
      home: VisionDemoScreen(
        apiBaseUrl: 'https://api.example.test/',
        imagePicker: picker,
        client: client,
        idTokenProvider: () async => 'token',
      ),
    );

// データを作らずに、容量確認だけで巨大ファイルを拒否することを確かめる。
class OversizedImage extends XFile {
  OversizedImage() : super('large.png', name: 'large.png');

  bool readRequested = false;

  @override
  Future<int> length() async => 20 * 1024 * 1024 + 1;

  @override
  Future<Uint8List> readAsBytes() async {
    readRequested = true;
    throw StateError('巨大ファイルのデータは読み込まない');
  }
}

// ネイティブ画像変換の完了を待ち、実際の変換結果で画面を検証する。
Future<void> chooseImage(WidgetTester tester, {bool wait = true}) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('画像を選択'));
    if (!wait) return;
    // 固定時間ではなく、変換の完了で選択ボタンが有効になるまで待つ。
    for (var attempt = 0; attempt < 500; attempt++) {
      await tester.pump();
      final button = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton).first,
      );
      if (button.onPressed != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('画像選択・変換が完了しませんでした');
  });
}

void main() {
  testWidgets('容量超過の画像はデータ読み込み前に拒否する', (tester) async {
    final file = OversizedImage();
    await tester.pumpWidget(screen(() async => file));
    await chooseImage(tester);
    await tester.pumpAndSettle();
    expect(find.text('画像は20MB以下のものを選んでください。'), findsOneWidget);
    expect(file.readRequested, isFalse);
    expect(find.text('判定する'), findsNothing);
  });

  testWidgets('画像選択をキャンセルすると再び選択できる', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      screen(() async => attempts++ == 0 ? null : image()),
    );
    await chooseImage(tester);
    await tester.pumpAndSettle();
    expect(find.text('判定する'), findsNothing);
    await chooseImage(tester);
    await tester.pumpAndSettle();
    expect(find.text('sample.png'), findsOneWidget);
  });

  testWidgets('画像選択中に画面を破棄しても状態更新しない', (tester) async {
    final selection = Completer<XFile?>();
    await tester.pumpWidget(screen(() => selection.future));
    await chooseImage(tester, wait: false);
    await tester.pumpWidget(const SizedBox());
    selection.complete(image());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('画像選択の例外を表示し再試行できる', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      screen(() async {
        if (attempts++ == 0) throw Exception('picker failed');
        return image();
      }),
    );
    await chooseImage(tester);
    await tester.pumpAndSettle();
    expect(find.text('画像を選択できませんでした。もう一度お試しください。'), findsOneWidget);
    await chooseImage(tester);
    await tester.pumpAndSettle();
    expect(find.text('sample.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('選択フィルターを通り抜けたWebPも拒否する', (tester) async {
    await tester.pumpWidget(screen(() async => image('sample.webp')));
    await chooseImage(tester);
    await tester.pumpAndSettle();
    expect(find.text('JPEG、PNG、HEIC/HEIFの画像を選んでください。'), findsOneWidget);
    expect(find.text('判定する'), findsNothing);
  });

  testWidgets('本文受信が止まっても90秒で判定中を解除する', (tester) async {
    final body = StreamController<List<int>>();
    // ヘッダーだけ受信し、本文が終了しない状況を再現する。
    final client = MockClient.streaming((request, stream) async {
      expect(
        request.url.toString(),
        'https://api.example.test/api/v1/vision-demo',
      );
      expect(request.headers['Authorization'], 'Bearer token');
      await stream.drain<void>();
      return http.StreamedResponse(body.stream, 200);
    });
    await tester.pumpWidget(screen(() async => image(), client: client));
    await chooseImage(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('判定する'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();
    expect(find.text('判定しています…'), findsNothing);
    expect(find.text('判定に失敗しました。接続を確認してもう一度お試しください。'), findsOneWidget);
    await body.close();
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('画面離脱後に判定が完了しても状態更新しない', (tester) async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    await tester.pumpWidget(screen(() async => image(), client: client));
    await chooseImage(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('判定する'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    response.complete(
      http.Response('{"categories": {"adult": "UNLIKELY"}}', 200),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    client.close();
  });
}
