import 'dart:typed_data';
import 'dart:ui' as ui;

// Local sample artwork: no external image host or production data is used.
Future<Uint8List> createPreviewArtwork(int variant) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const width = 720.0;
  const height = 960.0;
  final palettes = [
    [
      const ui.Color(0xFF142D54),
      const ui.Color(0xFFFFD7AD),
      const ui.Color(0xFF446C7C),
    ],
    [
      const ui.Color(0xFF173C70),
      const ui.Color(0xFFC7EDFF),
      const ui.Color(0xFF46687D),
    ],
    [
      const ui.Color(0xFF172442),
      const ui.Color(0xFFDCEBFF),
      const ui.Color(0xFF344B65),
    ],
  ];
  final colors = palettes[variant % palettes.length];
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, width, height),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        const ui.Offset(0, height),
        [colors[0], colors[1]],
      ),
  );
  canvas.drawCircle(
    const ui.Offset(520, 230),
    85,
    ui.Paint()..color = colors[1],
  );
  for (var layer = 0; layer < 3; layer++) {
    final y = 500.0 + layer * 140;
    final path = ui.Path()
      ..moveTo(0, y)
      ..cubicTo(180, y - 160, 420, y + 180, width, y - 40)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(
      path,
      ui.Paint()..color = ui.Color.lerp(colors[2], colors[0], layer / 3)!,
    );
  }
  final flower = ui.Paint()..color = colors[1];
  for (var i = 0; i < 16; i++) {
    final x = 45.0 + (i * 113 % 640);
    final y = 730.0 + (i * 47 % 190);
    canvas.drawLine(
      ui.Offset(x, y),
      ui.Offset(x, y + 35),
      ui.Paint()
        ..color = colors[2]
        ..strokeWidth = 3,
    );
    canvas.drawCircle(ui.Offset(x, y), 7, flower);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Unable to create preview image');
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}
