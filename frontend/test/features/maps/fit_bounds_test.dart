import 'package:edutrack_app/features/maps/presentation/fit_bounds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The box a map opens on (docs/maps.md, M2).
///
/// The rule it exists for: **a centre and a zoom is a guess.** A route
/// longer than the guess allowed for runs off the screen, and somebody who
/// does not think to pan reads it as a route that stops halfway.
void main() {
  group('the box around some places', () {
    test('it is the smallest one holding all of them', () {
      final framed = MapBounds.of(const [LatLng(18.5308, 73.8000), LatLng(18.5074, 73.8744), LatLng(18.5158, 73.8416)]);

      expect(framed, isNotNull);
      expect(framed!.bounds.southwest.latitude, closeTo(18.5074, 0.00001));
      expect(framed.bounds.southwest.longitude, closeTo(73.8000, 0.00001));
      expect(framed.bounds.northeast.latitude, closeTo(18.5308, 0.00001));
      expect(framed.bounds.northeast.longitude, closeTo(73.8744, 0.00001));
    });

    test('the order they arrive in does not matter', () {
      const points = [LatLng(1, 2), LatLng(-3, 4), LatLng(5, -6)];
      final forwards = MapBounds.of(points)!.bounds;
      final backwards = MapBounds.of(points.reversed)!.bounds;

      expect(backwards.southwest, forwards.southwest);
      expect(backwards.northeast, forwards.northeast);
    });

    test('it works across the equator and the meridian', () {
      final framed = MapBounds.of(const [LatLng(-1, -1), LatLng(1, 1)])!.bounds;

      expect(framed.southwest, const LatLng(-1, -1));
      expect(framed.northeast, const LatLng(1, 1));
    });

    test('two places in a line still make a box', () {
      // Same longitude, different latitude: flat, but not a point, and
      // Google is happy to frame it.
      final framed = MapBounds.of(const [LatLng(10, 20), LatLng(12, 20)]);

      expect(framed, isNotNull);
      expect(framed!.bounds.southwest.latitude, 10);
      expect(framed.bounds.northeast.latitude, 12);
    });
  });

  group('when there is no box to make', () {
    test('nowhere is not a box', () {
      expect(MapBounds.of(const []), isNull);
    });

    test('one place is not a box', () {
      // A box with no width leaves Google to pick a zoom, and it picks
      // street level - a worse answer than the centre and zoom the screen
      // already chose.
      expect(MapBounds.of(const [LatLng(18.5, 73.8)]), isNull);
    });

    test('the same place twice is one place', () {
      expect(MapBounds.of(const [LatLng(18.5, 73.8), LatLng(18.5, 73.8)]), isNull);
    });

    test('the same place many times is still one place', () {
      expect(MapBounds.of(const [LatLng(0, 0), LatLng(0, 0), LatLng(0, 0)]), isNull);
    });
  });
}
