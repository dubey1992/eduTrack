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
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );
}
