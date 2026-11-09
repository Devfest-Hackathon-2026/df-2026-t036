import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/models/artwork_image_format.dart';

Uint8List heifHeader({String brand = 'heic'}) {
  final bytes = Uint8List(24);
  ByteData.sublistView(bytes).setUint32(0, bytes.length);
  bytes.setRange(4, 8, 'ftyp'.codeUnits);
  bytes.setRange(8, 12, 'mif1'.codeUnits);
  bytes.setRange(16, 20, brand.codeUnits);
  bytes.setRange(20, 24, 'mif1'.codeUnits);
  return bytes;
}

void main() {
  test(
    'size boundary accepts exactly 30 MiB but rejects empty and oversized',
    () {
      expect(
        () => checkArtworkImageSize(maxArtworkImageBytes),
        returnsNormally,
      );
      for (final size in [0, -1, maxArtworkImageBytes + 1]) {
        expect(() => checkArtworkImageSize(size), throwsStateError);
      }
    },
  );
  test('WebP preflight checks container size and matching extension', () {
    final bytes = Uint8List(24);
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
    bytes.setRange(8, 12, 'WEBP'.codeUnits);
    bytes.setRange(12, 16, 'VP8L'.codeUnits);
    expect(
      checkArtworkImageFormat('drawing.WEBP', bytes),
      ArtworkImageFormat.webp,
    );
    expect(
      () => checkArtworkImageFormat('drawing.png', bytes),
      throwsStateError,
    );
    bytes[4] = 0;
    expect(
      () => checkArtworkImageFormat('drawing.webp', bytes),
      throwsStateError,
    );
  });
  test(
    'HEIF preflight recognizes compatible brands and rejects renamed AVIF',
    () {
      expect(
        checkArtworkImageFormat('drawing.heic', heifHeader()),
        ArtworkImageFormat.heif,
      );
      expect(
        checkArtworkImageFormat('drawing.heif', heifHeader(brand: 'heix')),
        ArtworkImageFormat.heif,
      );
      expect(
        () =>
            checkArtworkImageFormat('drawing.heic', heifHeader(brand: 'avif')),
        throwsStateError,
      );
      final truncated = heifHeader().sublist(0, 20);
      expect(
        () => checkArtworkImageFormat('drawing.heic', truncated),
        throwsStateError,
      );
    },
  );
}
