/// Where the attendant's phone is, asked for while a trip runs and the My
/// Trip screen is open - never in the background.
///
/// The Android app asks the platform through geolocator; the web build asks
/// the browser's Geolocation API through package:web. The split is by
/// conditional import (the pattern of core/utils/file_picker.dart), and
/// tests use a fake [LocationSource] instead of either.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_source_io.dart' if (dart.library.js_interop) 'location_source_web.dart' as platform;

/// Whether the phone will give its position, and if not, why.
enum LocationAccess { granted, denied, deniedForever, serviceOff, unsupported }

/// A position, as the device reported it.
class DevicePosition {
  const DevicePosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.speed,
    this.heading,
  });

  final double latitude;
  final double longitude;

  /// Metres.
  final double accuracy;
  final double? speed;
  final double? heading;
}

/// Thrown when a position cannot be had; [access] says why.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.access);

  final LocationAccess access;

  @override
  String toString() => 'LocationUnavailable($access)';
}

abstract class LocationSource {
  /// Asks for permission if it has not been answered yet, and reports the
  /// outcome. Safe to call again: an answered question is not asked twice.
  Future<LocationAccess> requestAccess();

  /// The current position. Throws [LocationUnavailable].
  Future<DevicePosition> currentPosition();
}

final locationSourceProvider = Provider<LocationSource>((ref) => platform.createLocationSource());
