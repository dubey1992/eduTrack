import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/utils/geo.dart';

/// Metres between two map points, as the crow flies.
///
/// A straight line is honest about being a straight line, where a road
/// distance would need a request, a key and a wait - and the question here
/// is only ever "is this stop near the school or on the other side of the
/// country?". The maths is core/utils/geo.dart, shared with a running
/// trip's "has the bus moved far enough to report?".
double distanceM(LatLng from, LatLng to) => metresBetween(from.latitude, from.longitude, to.latitude, to.longitude);

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
