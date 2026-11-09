import 'dart:typed_data';

Future<void> saveArtworkFile(
  Uint8List bytes,
  String filename, {
  required String contentType,
}) async =>
    throw UnsupportedError('File saving is available in a browser');
