import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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
  // A failed attempt must not poison every later one: an ad blocker
  // switched off, or a network that came back, should be able to try again.
  return _loading ??= _load(browserKey).onError((error, stack) {
    _loading = null;
    throw error!;
  });
}

Future<void> _load(String browserKey) async {
  // Something else may already have loaded it - a second copy would replace
  // the API object underneath a map that is using it.
  if (_ready()) return;

  if (!_alreadyThere()) await _inject(browserKey);

  // `loading=async` means the script tag finishes before the API is usable:
  // the bootstrap arrives, the libraries follow, and `google.maps` may not
  // exist at all in that gap. Creating a map there gives a grey box and no
  // error, which is a miserable thing to diagnose.
  await _waitForBootstrap();
  await _library('maps');
  await _library('marker');
}

/// Up to ten seconds for `google.maps.importLibrary` to appear. A slow
/// connection on a school's broadband is not a failure.
Future<void> _waitForBootstrap() async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (_ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  throw StateError('The Google Maps script loaded but the API never became usable.');
}

bool _ready() {
  final google = web.window.getProperty('google'.toJS) as JSObject?;
  final maps = google?.getProperty('maps'.toJS) as JSObject?;

  return maps != null && maps.has('importLibrary');
}

Future<void> _inject(String browserKey) async {
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

  await done.future;
}

/// `google.maps.importLibrary(name)`, which is how the asynchronous
/// bootstrap says a part of the API is ready to use.
Future<void> _library(String name) async {
  final google = web.window.getProperty('google'.toJS) as JSObject?;
  final maps = google?.getProperty('maps'.toJS) as JSObject?;

  if (maps == null) throw StateError('The Google Maps API did not load.');

  await (maps.callMethod('importLibrary'.toJS, name.toJS) as JSPromise).toDart;
}

/// Was a `_load` started by something other than this - the plugin's own
/// loader, or a script tag in the page?

bool _alreadyThere() => web.document.getElementById(_elementId) != null;
