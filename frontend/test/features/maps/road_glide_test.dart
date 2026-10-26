import 'package:edutrack_app/features/maps/data/road_glide.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// How the bus pin gets from one position to the next (docs/maps.md, "A
/// bus that glides"). The road here is an L in Pune: east along one street
/// for about 1 km, then north for about 1 km.
void main() {
  const corner = LatLng(18.5000, 73.8095);
  const road = [LatLng(18.5000, 73.8000), corner, LatLng(18.5090, 73.8095)];

  // On the east-west street, and on the north-south one.
  const beforeCorner = LatLng(18.5000, 73.8050);
  const afterCorner = LatLng(18.5045, 73.8095);

  test('two positions either side of a corner go round it, not across', () {
    final glide = RoadGlide.between(beforeCorner, afterCorner, road);

    expect(glide.points, contains(corner));
    // Straight across would be about 680 m; round the corner is about 975 m.
    expect(glide.metres, closeTo(975, 15));
  });

  test('half way is measured in metres, so it is past the corner here', () {
    final glide = RoadGlide.between(beforeCorner, afterCorner, road);

    final middle = glide.at(0.5);

    // 475 m to the corner, 500 m after it: half of 975 is 12 m past it.
    expect(middle.longitude, closeTo(corner.longitude, 0.0001));
    expect(middle.latitude, greaterThan(corner.latitude));
  });

  test('the ends are the two positions themselves', () {
    final glide = RoadGlide.between(beforeCorner, afterCorner, road);

    expect(glide.at(0), beforeCorner);
    expect(glide.at(1), afterCorner);
    expect(glide.at(1.7), afterCorner, reason: 'running late never overshoots');
  });

  test('a position off the road is reached in a straight line', () {
    const diversion = LatLng(18.5030, 73.8050); // 330 m north of the street

    final glide = RoadGlide.between(beforeCorner, diversion, road);

    expect(glide.points, [beforeCorner, diversion]);
  });

  test('going backwards along the road is a straight line, not a lap of the route', () {
    final glide = RoadGlide.between(afterCorner, beforeCorner, road);

    expect(glide.points, [afterCorner, beforeCorner]);
  });

  test('with no road, a straight line', () {
    final glide = RoadGlide.between(beforeCorner, afterCorner, const []);

    expect(glide.points, [beforeCorner, afterCorner]);
  });

  test('a bus that has not moved stays put', () {
    final glide = RoadGlide.between(beforeCorner, beforeCorner, road);

    expect(glide.metres, closeTo(0, 0.5));
    expect(glide.at(0.5).latitude, closeTo(beforeCorner.latitude, 1e-6));
  });
}
