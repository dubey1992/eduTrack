import 'package:edutrack_app/features/maps/presentation/distance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// How far a pin is from the school it belongs to (docs/maps.md).
///
/// The same haversine the server measures with (school/geo.py), so the
/// sentence under the map and the refusal that comes back from a save
/// cannot disagree about whether a stop is 90 km away or 110.
void main() {
  group('the distance itself', () {
    test('the same place is no distance at all', () {
      expect(distanceM(const LatLng(28.6139, 77.2090), const LatLng(28.6139, 77.2090)), closeTo(0, 0.001));
    });

    test('a degree of latitude is about 111 km, anywhere', () {
      // The one span that does not depend on where you are.
      expect(distanceM(const LatLng(0, 0), const LatLng(1, 0)), closeTo(111195, 500));
    });

    test('a degree of longitude shrinks towards the poles', () {
      // At 60 degrees north it is half what it is at the equator, which is
      // the error a flat subtraction of coordinates would make.
      final atTheEquator = distanceM(const LatLng(0, 0), const LatLng(0, 1));
      final farNorth = distanceM(const LatLng(60, 0), const LatLng(60, 1));

      expect(farNorth, closeTo(atTheEquator / 2, 2000));
    });

    test('Delhi to Mumbai is about 1150 km', () {
      // A real pair, because a formula that is wrong by a factor is easiest
      // to catch against a distance somebody knows.
      expect(distanceM(const LatLng(28.6139, 77.2090), const LatLng(19.0760, 72.8777)), closeTo(1150000, 20000));
    });

    test('it does not care which way round the two points are', () {
      const school = LatLng(28.6139, 77.2090);
      const stop = LatLng(28.6200, 77.2100);

      expect(distanceM(school, stop), closeTo(distanceM(stop, school), 0.001));
    });
  });

  group('how it reads', () {
    test('under a kilometre is metres, because 0.45 km is hard to picture', () {
      expect(formatDistance(450), '450 m');
      expect(formatDistance(999), '999 m');
    });

    test('above it is kilometres, to one place', () {
      expect(formatDistance(1000), '1.0 km');
      expect(formatDistance(2449), '2.4 km');
    });

    test('a second decimal place never changed anybody\'s mind', () {
      expect(formatDistance(2449), isNot(contains('2.45')));
    });
  });
}
