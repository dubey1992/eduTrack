import 'package:geolocator/geolocator.dart';

import 'location_source.dart';

LocationSource createLocationSource() => GeolocatorLocationSource();

/// The Android app's positions, from the platform's location service.
/// Foreground only: the manifest asks for no background location.
class GeolocatorLocationSource implements LocationSource {
  @override
  Future<LocationAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();

    return switch (permission) {
      LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.unableToDetermine => LocationAccess.unsupported,
      LocationPermission.denied => LocationAccess.denied,
    };
  }

  @override
  Future<DevicePosition> currentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      return DevicePosition(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        // The platform reports 0 or less when it does not know.
        speed: position.speed > 0 ? position.speed : null,
        heading: position.heading >= 0 ? position.heading : null,
        isMocked: position.isMocked,
        takenAt: position.timestamp,
      );
    } on LocationServiceDisabledException {
      throw const LocationUnavailable(LocationAccess.serviceOff);
    } on PermissionDeniedException {
      throw const LocationUnavailable(LocationAccess.denied);
    }
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Stream<DevicePosition> positions({required Duration interval, required double distanceFilterMetres}) {
    // Both filters go to the platform rather than being applied here, so
    // the app is not woken to throw a position away: Android holds one
    // location request and delivers only what passes both.
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMetres.round(),
      intervalDuration: interval,
    );

    return Geolocator.getPositionStream(locationSettings: settings)
        .map(
          (position) => DevicePosition(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            speed: position.speed > 0 ? position.speed : null,
            heading: position.heading >= 0 ? position.heading : null,
          ),
        )
        .handleError(
          (Object error) => throw switch (error) {
            LocationServiceDisabledException() => const LocationUnavailable(LocationAccess.serviceOff),
            PermissionDeniedException() => const LocationUnavailable(LocationAccess.denied),
            _ => error,
          },
        );
  }
}
