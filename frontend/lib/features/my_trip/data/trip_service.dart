/// Keeping the app alive while a trip is running (docs/driver-app.md, D4).
///
/// The split is by conditional import, the pattern of location_source.dart:
/// Android starts a foreground service, the web build does nothing, and
/// tests use a fake instead of either.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trip_service_io.dart' if (dart.library.js_interop) 'trip_service_web.dart' as platform;

/// What keeps the phone awake and reporting while a trip runs.
abstract class TripService {
  /// Starts it, or updates the notification if it is already running.
  Future<void> start({required String title, required String body});

  Future<void> stop();
}

class PlatformTripService implements TripService {
  const PlatformTripService();

  @override
  Future<void> start({required String title, required String body}) => platform.start(title: title, body: body);

  @override
  Future<void> stop() => platform.stop();
}

final tripServiceProvider = Provider<TripService>((ref) => const PlatformTripService());
