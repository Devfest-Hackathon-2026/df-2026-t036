import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/screens/artwork_composer_screen.dart';
import 'artwork_image_format_test.dart' show heifHeader;

Future<Uint8List> samplePng() async {
  // 実際にデコードできる小さな画像をメモリ内で作り、外部ファイルに依存しない。
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  // 非対応形式の選択と、拡張子だけPNG/JPEGへ変更した画像を拒否する。
  for (final name in [
    'image.webp',
    'image.gif',
    'image.heic',
    'image.png',
    'image.jpeg',
  ]) {
    testWidgets('$name の非対応データを拒否する', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ArtworkComposerScreen(
            ideaId: 'idea',
            ideaTitle: 'お題',
            ideaCreatedAt: DateTime(2026, 11, 7),
            pickImage: () async => XFile.fromData(
              Uint8List.fromList([
                0x52,
                0x49,
                0x46,
                0x46,
                0,
                0,
                0,
                0,
                0x57,
                0x45,
                0x42,
                0x50,
              ]),
              name: name,
              path: name,
            ),
          ),
        ),
      );
      await tester.tap(find.text('イラストを選択'));
      await tester.pumpAndSettle();
      expect(find.text('PNG・JPEG・WebP・HEIC/HEIFの画像を選択してください。'), findsOneWidget);
      expect(find.byKey(const ValueKey('artwork-preview')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('artwork-send-demo')),
            )
            .onPressed,
        isNull,
      );
    });
  }
  // スマホの標準文字サイズでは、画像追加と送信操作が一画面に収まる。
  for (final size in [const Size(375, 667), const Size(390, 844)]) {
    testWidgets('スマホ $size で16対9の追加領域と送信操作を表示する', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ArtworkComposerScreen(
            ideaId: 'idea',
            ideaTitle: '夜明けの庭',
            ideaCreatedAt: DateTime(2026, 11, 7),
            ideaTags: const ['風景'],
          ),
        ),
      );
      final area = tester.getSize(find.byType(AspectRatio));
      expect(area.width / area.height, closeTo(16 / 9, 0.001));
      final send = tester.getRect(
        find.byKey(const ValueKey('artwork-send-demo')),
      );
      expect(send.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('未選択では送信不可で、選択キャンセルしても空のまま', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkComposerScreen(
          ideaId: 'idea',
          ideaTitle: 'お題',
          ideaCreatedAt: DateTime(2026, 11, 7),
          ideaTags: const ['風景'],
          pickImage: () async => null,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('artwork-target-idea')), findsOneWidget);
    expect(find.text('#風景'), findsOneWidget);
    expect(find.text('2026.11.07'), findsOneWidget);
    final send = find.byKey(const ValueKey('artwork-send-demo'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.ensureVisible(find.text('イラストを選択'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('イラストを選択'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artwork-preview')), findsNothing);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
  });

  testWidgets('画像プレビュー・選び直しキャンセル・確認・デモ完了', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final png = await tester.runAsync(samplePng);
    var picks = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('ホーム画面')),
      ),
    );
    // 詳細画面を経由しても、完了ボタンで途中の画面を残さず戻る。
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) => const Scaffold(body: Text('詳細画面')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) => ArtworkComposerScreen(
          ideaId: 'idea',
          ideaTitle: '夜明けの庭',
          ideaCreatedAt: DateTime(2026, 11, 7),
          ideaTags: const ['風景'],
          pickImage: () async => ++picks == 1
              ? XFile.fromData(png!, name: 'garden.png', path: 'garden.png')
              : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('イラストを選択'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('イラストを選択'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artwork-preview')), findsOneWidget);
    expect(find.text('garden.png'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('artwork-reselect')));
    await tester.tap(find.byKey(const ValueKey('artwork-reselect')));
    await tester.pumpAndSettle();
    expect(find.text('garden.png'), findsOneWidget);
    expect(find.byKey(const ValueKey('artwork-target-idea')), findsOneWidget);
    expect(find.text('#風景'), findsOneWidget);
    expect(find.text('2026.11.07'), findsOneWidget);
    final send = find.byKey(const ValueKey('artwork-send-demo'));
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.textContaining('「夜明けの庭」'), findsOneWidget);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artwork-preview')), findsOneWidget);
    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('artwork-confirm-demo')));
    await tester.pumpAndSettle();
    expect(find.text('送信完了（デモ）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('artwork-complete-check')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('artwork-target-idea')), findsNothing);
    expect(find.text('これはデモです。画像は送信・保存されていません。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artwork-return-home')));
    await tester.pumpAndSettle();
    expect(find.text('ホーム画面'), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
  });

  testWidgets('非対応形式を選ぶとエラーで送信不可', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkComposerScreen(
          ideaId: 'idea',
          ideaTitle: 'お題',
          ideaCreatedAt: DateTime(2026, 11, 7),
          ideaTags: const ['風景'],
          pickImage: () async =>
              XFile.fromData(Uint8List.fromList([1]), name: 'work.psd'),
        ),
      ),
    );
    await tester.ensureVisible(find.text('イラストを選択'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('イラストを選択'));
    await tester.pumpAndSettle();
    expect(find.text('PNG・JPEG・WebP・HEIC/HEIFの画像を選択してください。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('artwork-send-demo')))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'HEIF without browser decoding is selected but cannot be submitted unseen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ArtworkComposerScreen(
            ideaId: 'idea',
            ideaTitle: 'お題',
            ideaCreatedAt: DateTime(2026, 11, 7),
            pickImage: () async => XFile.fromData(
              heifHeader(),
              name: 'drawing.heic',
              path: 'drawing.heic',
            ),
          ),
        ),
      );
      await tester.tap(find.text('イラストを選択'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('drawing.heic'), findsOneWidget);
      expect(find.textContaining('このHEIC/HEIFはブラウザで表示できません'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('artwork-send-demo')),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('rejecting a replacement clears the previously selected image', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final png = await tester.runAsync(samplePng);
    var picks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkComposerScreen(
          ideaId: 'idea',
          ideaTitle: 'お題',
          ideaCreatedAt: DateTime(2026, 11, 7),
          pickImage: () async => ++picks == 1
              ? XFile.fromData(png!, name: 'valid.png', path: 'valid.png')
              : XFile.fromData(
                  Uint8List.fromList([1]),
                  name: 'bad.png',
                  path: 'bad.png',
                ),
        ),
      ),
    );
    await tester.tap(find.text('イラストを選択'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artwork-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artwork-reselect')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artwork-preview')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('artwork-send-demo')))
          .onPressed,
      isNull,
    );
  });
}
