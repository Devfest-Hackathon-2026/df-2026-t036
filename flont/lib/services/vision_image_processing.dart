import 'dart:typed_data';
import 'dart:ui' as ui;

// Flutter側の変換は早期検査であり、サーバーでも必ず再検証する。
Future<Uint8List> prepareVisionImage(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > 40000000) {
        throw StateError('画像の縦横サイズが上限を超えています。');
      }
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longest > 2560 ? 2560 / longest : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, 2560),
        targetHeight: (descriptor.height * scale).round().clamp(1, 2560),
      );
      try {
        if (codec.frameCount != 1) throw StateError('静止画を1枚選択してください。');
        final frame = await codec.getNextFrame();
        try {
          // 透過を保ち、元画像のメタデータを引き継がずPNGへ変換する。
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null) throw StateError('画像を変換できませんでした。');
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
