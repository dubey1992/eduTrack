import 'dart:math' as math;

/// Metres between two points, as the crow flies.
///
/// The same haversine the server uses (school/geo.py). It lives in core
/// because two features ask the question for different reasons: the maps
/// screens, to say how far a stop is from its school, and a running trip,
/// to decide whether the bus has moved far enough to be worth reporting.
double metresBetween(double fromLat, double fromLng, double toLat, double toLng) {
  const earthRadiusM = 6371008.8;

  final lat1 = _radians(fromLat);
  final lat2 = _radians(toLat);
  final deltaLat = _radians(toLat - fromLat);
  final deltaLng = _radians(toLng - fromLng);

  final a = math.pow(math.sin(deltaLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLng / 2), 2);

  return 2 * earthRadiusM * math.asin(math.sqrt(a.toDouble()));
}

double _radians(double degrees) => degrees * math.pi / 180;
