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
      );
    } on LocationServiceDisabledException {
      throw const LocationUnavailable(LocationAccess.serviceOff);
    } on PermissionDeniedException {
      throw const LocationUnavailable(LocationAccess.denied);
    }
  }
}
