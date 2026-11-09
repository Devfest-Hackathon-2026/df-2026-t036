import 'dart:typed_data';

// Client-side preflight only. The server must validate the complete image again.
enum ArtworkImageFormat { png, jpeg, webp, heif }

const maxArtworkImageBytes = 30 * 1024 * 1024;
const artworkImageFormatError = 'PNG・JPEG・WebP・HEIC/HEIFの画像を選択してください。';

void checkArtworkImageSize(int length) {
  if (length <= 0 || length > maxArtworkImageBytes) {
    throw StateError('空でない30MB以内の画像を選択してください。');
  }
}

ArtworkImageFormat checkArtworkImageFormat(String filename, Uint8List bytes) {
  checkArtworkImageSize(bytes.length);
  final extension = filename.split('.').last.toLowerCase();
  bool matches(int offset, List<int> signature) =>
      bytes.length >= offset + signature.length &&
      List.generate(
        signature.length,
        (i) => bytes[offset + i] == signature[i],
      ).every((value) => value);
  String tag(int start) =>
      String.fromCharCodes(bytes.sublist(start, start + 4));
  if (extension == 'png' && matches(0, [137, 80, 78, 71, 13, 10, 26, 10])) {
    return ArtworkImageFormat.png;
  }
  if (['jpg', 'jpeg'].contains(extension) && matches(0, [255, 216, 255])) {
    return ArtworkImageFormat.jpeg;
  }
  // https://developers.google.com/speed/webp/docs/riff_container
  if (extension == 'webp' &&
      bytes.length >= 20 &&
      tag(0) == 'RIFF' &&
      tag(8) == 'WEBP' &&
      ByteData.sublistView(bytes).getUint32(4, Endian.little) + 8 ==
          bytes.length &&
      ['VP8 ', 'VP8L', 'VP8X'].contains(tag(12))) {
    return ArtworkImageFormat.webp;
  }
  // https://www.loc.gov/preservation/digital/formats/fdd/fdd000526.shtml
  // HEIF file-type box: major brand plus compatible brands (not the filename).
  if (['heic', 'heif'].contains(extension) &&
      bytes.length >= 16 &&
      tag(4) == 'ftyp') {
    final size = ByteData.sublistView(bytes).getUint32(0);
    if (size >= 16 && size <= bytes.length && (size - 16) % 4 == 0) {
      final brands = [tag(8), for (var i = 16; i < size; i += 4) tag(i)];
      if (!brands.any(['avif', 'avis'].contains) &&
          brands.any(['heic', 'heix', 'heim', 'heis', 'mif1'].contains)) {
        return ArtworkImageFormat.heif;
      }
    }
  }
  throw StateError(artworkImageFormatError);
}
