import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves bytes through the browser, by handing it a blob and clicking a link
/// at it - the only way a web page can produce a file.
///
/// The object URL is released immediately afterwards: each one pins its blob
/// in memory for the life of the tab, and a report run twenty times would
/// otherwise hold twenty copies.
void saveBytes({required String fileName, required List<int> bytes, required String mimeType}) {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();

  web.URL.revokeObjectURL(url);
}
