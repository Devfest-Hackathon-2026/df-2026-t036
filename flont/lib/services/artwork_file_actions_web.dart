import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

web.File _file(Uint8List bytes, String filename, String contentType) => web.File(
  [bytes.toJS].toJS,
  filename,
  web.FilePropertyBag(type: contentType),
);

Future<void> saveArtworkFile(
  Uint8List bytes,
  String filename, {
  required String contentType,
}) async {
  final url = web.URL.createObjectURL(_file(bytes, filename, contentType));
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  try {
    web.document.body!.appendChild(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
}
