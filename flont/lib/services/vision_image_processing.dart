import 'dart:typed_data';
import 'dart:ui' as ui;

// Webでも利用できるCodecでデコードし、フレームの実寸から検証する。
Future<ui.Image> decodeArtworkImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    if (codec.frameCount != 1) throw StateError('静止画を1枚選択してください。');
    final frame = await codec.getNextFrame();
    final image = frame.image;
    if (image.width * image.height > 40000000) {
      image.dispose();
      throw StateError('画像の縦横サイズが上限を超えています。');
    }
    // 呼び出し元が処理後にimage.dispose()で解放する。
    return image;
  } finally {
    codec.dispose();
  }
}

// デコード済み画像を共用し、プレビューと送信用に二重デコードしない。
Future<Uint8List> encodeVisionImage(ui.Image source) async {
  final longest = source.width > source.height ? source.width : source.height;
  final scale = longest > 2560 ? 2560 / longest : 1.0;
  final width = (source.width * scale).round().clamp(1, 2560);
  final height = (source.height * scale).round().clamp(1, 2560);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // 透過を維持し、元ファイルのメタデータを引き継がず描画し直す。
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('画像を変換できませんでした。');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

// Flutter側の変換は早期検査であり、サーバーでも必ず再検証する。
Future<Uint8List> prepareVisionImage(Uint8List bytes) async {
  final image = await decodeArtworkImage(bytes);
  try {
    return await encodeVisionImage(image);
  } finally {
    image.dispose();
  }
}
