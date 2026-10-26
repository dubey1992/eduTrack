import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/utils/geo.dart';

/// The way a bus pin gets from where it was drawn to where the bus is now
/// (docs/maps.md, "A bus that glides").
///
/// The office's map hears from the bus every fifteen seconds or so, and a
/// pin that jumped to each new position would hop a few hundred metres at a
/// time and cut across every corner. So the pin is moved along the road
/// between the two positions instead - the route's own road where both
/// positions are on it and the bus has gone forwards along it, a straight
/// line otherwise (off the route, or reversing).
///
/// Pure arithmetic on points, so it is tested without a map.
class RoadGlide {
  RoadGlide._(this._points, this._cumulative);

  /// The way from [from] to [to]: along [road] where that makes sense,
  /// straight otherwise.
  factory RoadGlide.between(LatLng from, LatLng to, List<LatLng> road) {
    final along = _alongRoad(from, to, road);

    return RoadGlide._fromPoints(along ?? [from, to]);
  }

  factory RoadGlide._fromPoints(List<LatLng> points) {
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + _metres(points[i - 1], points[i]));
    }

    return RoadGlide._(points, cumulative);
  }

  /// Further from the road than this, a position is not on it: a GPS fix
  /// wanders a little, a bus on a diversion is somewhere else.
  static const onRoadMetres = 60.0;

  final List<LatLng> _points;
  final List<double> _cumulative;

  /// The whole way, in metres.
  double get metres => _cumulative.last;

  /// The points the pin passes through - for a test to check which way it
  /// was sent.
  List<LatLng> get points => List.unmodifiable(_points);

  /// Where the pin is [fraction] of the way along (0 = where it was, 1 =
  /// where the bus is now), by distance rather than by point count, so it
  /// moves at an even pace however unevenly the road's points are spaced.
  LatLng at(double fraction) {
    final t = fraction.clamp(0.0, 1.0);
    if (metres == 0 || t == 1) return _points.last;

    final target = metres * t;
    var i = 1;
    while (i < _cumulative.length - 1 && _cumulative[i] < target) {
      i++;
    }

    final segment = _cumulative[i] - _cumulative[i - 1];
    final part = segment == 0 ? 0.0 : (target - _cumulative[i - 1]) / segment;
    final a = _points[i - 1];
    final b = _points[i];

    return LatLng(a.latitude + (b.latitude - a.latitude) * part, a.longitude + (b.longitude - a.longitude) * part);
  }

  /// The road between the two positions, or null when it would be wrong to
  /// use it: no road, either position off it, or the bus going backwards.
  static List<LatLng>? _alongRoad(LatLng from, LatLng to, List<LatLng> road) {
    if (road.length < 2) return null;

    final start = _project(from, road);
    final end = _project(to, road);
    if (start == null || end == null) return null;
    if (start.distance > onRoadMetres || end.distance > onRoadMetres) return null;

    final startAt = start.segment + start.part;
    final endAt = end.segment + end.part;
    if (endAt < startAt) return null;

    return [from, start.point, for (var i = start.segment + 1; i <= end.segment; i++) road[i], end.point, to];
  }

  /// The nearest point on [road] to [p]: which segment, how far along it
  /// (0-1), the point itself, and how far away it is.
  static ({int segment, double part, LatLng point, double distance})? _project(LatLng p, List<LatLng> road) {
    ({int segment, double part, LatLng point, double distance})? best;

    // Flat x/y in metres around p, which is plenty for a few hundred
    // metres of street and much cheaper than great circles per segment.
    final metresPerDegreeLat = 111320.0;
    final metresPerDegreeLng = 111320.0 * math.cos(p.latitude * math.pi / 180);

    for (var i = 0; i < road.length - 1; i++) {
      final ax = (road[i].longitude - p.longitude) * metresPerDegreeLng;
      final ay = (road[i].latitude - p.latitude) * metresPerDegreeLat;
      final bx = (road[i + 1].longitude - p.longitude) * metresPerDegreeLng;
      final by = (road[i + 1].latitude - p.latitude) * metresPerDegreeLat;
      final dx = bx - ax;
      final dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      final part = lengthSquared == 0 ? 0.0 : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0);
      final x = ax + dx * part;
      final y = ay + dy * part;
      final distance = math.sqrt(x * x + y * y);

      if (best == null || distance < best.distance) {
        best = (
          segment: i,
          part: part,
          point: LatLng(
            road[i].latitude + (road[i + 1].latitude - road[i].latitude) * part,
            road[i].longitude + (road[i + 1].longitude - road[i].longitude) * part,
          ),
          distance: distance,
        );
      }
    }

    return best;
  }

  static double _metres(LatLng a, LatLng b) => metresBetween(a.latitude, a.longitude, b.latitude, b.longitude);
}
