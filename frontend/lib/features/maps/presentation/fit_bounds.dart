import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Opening a map on everything it has to show (docs/maps.md, M2).
///
/// A map built from a centre and a zoom is a guess, and it is wrong as soon
/// as a route is longer than the guess allowed for: the stops at the far end
/// are off the screen, and somebody who does not think to pan concludes the
/// route stops halfway. The camera is moved once, when the map is created,
/// to the smallest box holding every point.
class MapBounds {
  const MapBounds._(this.bounds);

  /// Null when there is nothing to frame, or when everything is in the same
  /// place - a box with no width leaves Google to pick a zoom, and it picks
  /// street level, which is a worse answer than the centre and zoom the
  /// screen already chose. One point is that case, so it needs no check of
  /// its own.
  static MapBounds? of(Iterable<LatLng> points) {
    if (points.isEmpty) return null;

    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;

    for (final point in points) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }

    if (south == north && west == east) return null;

    return MapBounds._(LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)));
  }

  final LatLngBounds bounds;
}

/// Moves a newly created map onto [points], if there is a box to move it to.
///
/// A camera that will not move is a map at the wrong zoom - a nuisance, and
/// not worth turning a working screen into an error - so the failure is
/// logged and the map is left where the screen put it. The platform does
/// refuse this: a map asked to frame a box before it has been given a size
/// has nothing to compute a zoom against.
Future<void> fitCamera(GoogleMapController controller, Iterable<LatLng> points, {double padding = 48}) async {
  final framed = MapBounds.of(points);

  if (framed == null) return;

  try {
    await controller.moveCamera(CameraUpdate.newLatLngBounds(framed.bounds, padding));
  } catch (error) {
    debugPrint('Could not frame the map on its points: $error');
  }
}
