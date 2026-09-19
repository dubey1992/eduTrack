import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'location_source.dart';

LocationSource createLocationSource() => BrowserLocationSource();

/// The web build's positions, from the browser's Geolocation API. The
/// browser asks the person itself the first time a position is wanted, so
/// asking for access is simply asking for a position.
class BrowserLocationSource implements LocationSource {
  // The W3C error codes.
  static const _permissionDenied = 1;

  @override
  Future<LocationAccess> requestAccess() async {
    try {
      await currentPosition();
      return LocationAccess.granted;
    } on LocationUnavailable catch (e) {
      return e.access;
    }
  }

  @override
  Future<DevicePosition> currentPosition() {
    final completer = Completer<DevicePosition>();

    void succeeded(web.GeolocationPosition position) {
      final coords = position.coords;
      completer.complete(
        DevicePosition(
          latitude: coords.latitude,
          longitude: coords.longitude,
          accuracy: coords.accuracy,
          speed: coords.speed,
          heading: coords.heading,
        ),
      );
    }

    void failed(web.GeolocationPositionError error) {
      completer.completeError(
        LocationUnavailable(error.code == _permissionDenied ? LocationAccess.denied : LocationAccess.serviceOff),
      );
    }

    web.window.navigator.geolocation.getCurrentPosition(
      succeeded.toJS,
      failed.toJS,
      web.PositionOptions(enableHighAccuracy: true, timeout: 10000, maximumAge: 5000),
    );

    return completer.future;
  }
}
