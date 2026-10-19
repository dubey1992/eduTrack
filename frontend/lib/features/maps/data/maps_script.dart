/// Makes sure the platform can draw a Google map before one is created.
///
/// On the web that means the Maps JavaScript API has to be on the page, and
/// it is fetched at runtime with the key the server handed out rather than
/// written into `index.html` - so no key is ever baked into a build and one
/// can be rotated without shipping another.
///
/// On Android the SDK is part of the app and there is nothing to wait for,
/// so the stub returns at once.
library;

export 'maps_script_stub.dart' if (dart.library.js_interop) 'maps_script_web.dart';
