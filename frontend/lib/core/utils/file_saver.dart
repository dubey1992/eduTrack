/// Hands a generated file to the person who asked for it.
///
/// The web build uses the browser's own download mechanism; anything else
/// gets the stub, which says plainly that it is not wired up rather than
/// failing silently. Reports are a web feature today - see docs/reports.md.
library;

export 'file_saver_stub.dart' if (dart.library.js_interop) 'file_saver_web.dart';
