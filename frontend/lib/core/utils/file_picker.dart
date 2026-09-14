/// Asks the person for a file from their own machine.
///
/// The mirror image of saveBytes() in file_saver.dart: the web build uses a
/// hidden `<input type="file">`, which is the only way a web page can read a
/// local file, and anything else gets the stub. Bulk upload is a web feature
/// today - see docs/imports.md.
library;

export 'file_picker_stub.dart' if (dart.library.js_interop) 'file_picker_web.dart';
export 'picked_file.dart';
