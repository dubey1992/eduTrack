import 'dart:developer' as developer;
import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external factory _DateTimeFormat();
  external _ResolvedOptions resolvedOptions();
}

extension type _ResolvedOptions._(JSObject _) implements JSObject {
  external String? get timeZone;
}

/// What `Intl.DateTimeFormat().resolvedOptions().timeZone` says, or null
/// when the browser will not say.
String? browserTimezone() {
  try {
    final zone = _DateTimeFormat().resolvedOptions().timeZone;

    return zone == null || zone.isEmpty ? null : zone;
  } catch (error) {
    // An old browser without the Intl API: the form goes without it.
    developer.log('No timezone from the browser', name: 'browser_timezone', error: error);
    return null;
  }
}
