import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Puts the Maps JavaScript API on the page, once, and waits for it.
///
/// `google_maps_flutter_web` expects the API to be loaded already; creating a
/// map before it is throws, and the screen shows a red box rather than a map.
/// So every map waits on this first.
///
/// The script is fetched with the key the server handed out, which is why it
/// is added here rather than written into `index.html`: a key in the HTML is
/// a key baked into the build, and rotating it would mean shipping another.
const _elementId = 'google-maps-js-api';

/// One future for the whole tab. Several maps on one screen, or a screen
/// opened twice, must not each add a script tag - the second load would
/// replace the API object underneath a map that is already using it.
Future<void>? _loading;

Future<void> ensureMapsReady(String browserKey) {
  return _loading ??= _load(browserKey);
}

Future<void> _load(String browserKey) async {
  if (_alreadyThere()) return;

  final done = Completer<void>();
  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..id = _elementId
    ..type = 'text/javascript'
    ..async = true
    // `loading=async` is what Google asks for when the script is added this
    // way; without it the console warns on every page load.
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$browserKey&loading=async&libraries=maps,marker';

  script.onload = (web.Event _) {
    if (!done.isCompleted) done.complete();
  }.toJS;

  // A refused key, a blocked network, an ad blocker. The map says it is
  // unavailable and the screen beside it carries on, which is the same
  // answer as having no key at all.
  script.onerror = (web.Event _) {
    if (!done.isCompleted) {
      done.completeError(StateError('The Google Maps script could not be loaded.'));
    }
    // Left on the page it would stop a later attempt from trying again.
    script.remove();
    _loading = null;
  }.toJS;

  web.document.head!.appendChild(script);

  return done.future;
}

bool _alreadyThere() => web.document.getElementById(_elementId) != null;
