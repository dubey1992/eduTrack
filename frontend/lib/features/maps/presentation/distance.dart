import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Metres between two points, as the crow flies.
///
/// The same haversine the server uses (school/geo.py) and for the same
/// reason: a straight line is honest about being a straight line, where a
/// road distance would need a request, a key and a wait - and the question
/// here is only ever "is this stop near the school or on the other side of
/// the country?".
double distanceM(LatLng from, LatLng to) {
  const earthRadiusM = 6371008.8;

  final lat1 = _radians(from.latitude);
  final lat2 = _radians(to.latitude);
  final deltaLat = _radians(to.latitude - from.latitude);
  final deltaLng = _radians(to.longitude - from.longitude);

  final a = math.pow(math.sin(deltaLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLng / 2), 2);

  return 2 * earthRadiusM * math.asin(math.sqrt(a.toDouble()));
}

double _radians(double degrees) => degrees * math.pi / 180;

/// "450 m" or "2.4 km" - what somebody reads to decide whether a pin is in
/// the right street or the wrong city.
///
/// Metres under a kilometre, because 0.45 km is harder to picture than
/// 450 m; one decimal place above it, because the second never changes a
/// decision.
String formatDistance(double metres) {
  if (metres < 1000) return '${metres.round()} m';

  return '${(metres / 1000).toStringAsFixed(1)} km';
}
