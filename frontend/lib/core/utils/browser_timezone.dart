/// The visitor's own timezone name - "Asia/Kolkata", "Africa/Lagos" - for a
/// form a stranger fills in, so whoever calls back knows what "morning"
/// meant to them.
///
/// The browser knows it; elsewhere this answers null rather than guessing.
/// Only ever a hint: the server keeps it when it is a real zone and drops it
/// otherwise.
library;

export 'browser_timezone_stub.dart' if (dart.library.js_interop) 'browser_timezone_web.dart';
