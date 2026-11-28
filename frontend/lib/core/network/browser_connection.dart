/// What the browser says about the connection (docs/offline-web.md, O1):
/// whether it believes it is online now, and each change from then on.
///
/// Outside a browser there is nothing to ask: always online and no changes,
/// so the phone apps behave exactly as before - they have their own handling
/// of a lost signal.
library;

export 'browser_connection_stub.dart' if (dart.library.js_interop) 'browser_connection_web.dart';
