import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/services/vision_image_processing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('長辺を2560pxへ縮小し、透過を保ってPNGへ変換する', () async {
    // 横長の透過画像から、実際の出力形式・寸法・透過を検証する。
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final source = await picture.toImage(3000, 300);
    final data = await source.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    picture.dispose();
    final prepared = await prepareVisionImage(data!.buffer.asUint8List());
    expect(prepared.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(prepared);
    final frame = await codec.getNextFrame();
    try {
      expect(frame.image.width, 2560);
      expect(frame.image.height, 256);
      final rgba = await frame.image.toByteData();
      expect(rgba!.getUint8(3), 0);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });
}
