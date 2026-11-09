import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/services/vision_image_processing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('実際のJPEGをWeb対応の経路でPNGへ変換する', () async {
    // PNGだけでなく、実JPEGのデコードから再出力まで確認する。
    final prepared = await prepareVisionImage(
      base64Decode(
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAIAAwDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDnKKKK9g8s/9k=',
      ),
    );
    expect(prepared.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final image = await decodeArtworkImage(prepared);
    try {
      expect(image.width, 12);
      expect(image.height, 8);
    } finally {
      image.dispose();
    }
  });

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
