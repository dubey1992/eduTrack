import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation_session_io.dart' if (dart.library.js_interop) 'navigation_session_web.dart' as platform;

/// Why navigation could not start, in the words the crew needs.
enum NavigationOutcome {
  /// Guidance is running.
  guiding,

  /// The driver was shown Google's terms and said no. Their choice, and it
  /// is remembered by the SDK - so this is not an error to shout about.
  termsRefused,

  /// The Navigation SDK is not switched on for this build's API key, or the
  /// device cannot run it. The stop still gets there: the caller falls back
  /// to handing it to Google Maps.
  unavailable,

  /// A route to the stop could not be found - no road, or no signal.
  noRoute,
}

/// Turn-by-turn guidance drawn inside this app (docs/driver-app.md, D7).
///
/// Behind an interface for the three reasons everything else here is: the
/// web build has no such SDK, tests must not talk to Google, and the app
/// keeps working when the SDK says no - the Navigate button falls back to
/// the Google Maps hand-off that shipped in D5.1.
abstract class NavigationSession {
  /// Whether this build can run guidance at all. False on the web, and on
  /// a phone whose key has no Navigation SDK behind it.
  Future<bool> isSupported();

  /// Asks Google's terms once, then starts guidance to the stop.
  Future<NavigationOutcome> guideTo({required double latitude, required double longitude, required String stopName});

  /// Ends guidance and releases the session. Safe to call when nothing is
  /// running.
  Future<void> stop();

  /// The map and its turn cards. Only meaningful once [guideTo] has
  /// answered [NavigationOutcome.guiding].
  Widget view();
}

final navigationSessionProvider = Provider<NavigationSession>((ref) => platform.createNavigationSession());
