import 'package:flutter/foundation.dart';

/// Environment configuration, overridable per build via --dart-define.
///
/// Example:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
class Env {
  const Env._();

  /// Base URL for the Laravel API, including the /api/v1 version prefix.
  ///
  /// Defaults to localhost, which works for web/desktop. Android emulators
  /// must reach the host machine via 10.0.2.2 instead of localhost, so pass
  /// --dart-define=API_BASE_URL=... when running on an emulator.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000/api/v1');

  /// Whether the build was told where the API is.
  static const bool apiBaseUrlGiven = bool.hasEnvironment('API_BASE_URL');

  /// Stops a release build that was not told where the API is, at start-up,
  /// with a message saying so (docs/security.md, "The phone apps").
  ///
  /// The localhost default is for development. Shipped, it would mean an app
  /// that talks plain HTTP to whatever answers on the phone's own port -
  /// which Android refuses, so the failure would look like "no connection"
  /// rather than "built wrong". Failing loudly here makes the mistake the
  /// build's, found by whoever built it, not a school's.
  static void checkReleaseConfiguration() {
    if (kReleaseMode && !apiBaseUrlGiven) {
      throw StateError('This release build has no API address. Build it with --dart-define=API_BASE_URL=https://...');
    }
  }
}
