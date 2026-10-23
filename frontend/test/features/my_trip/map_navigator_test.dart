import 'package:edutrack_app/features/my_trip/data/map_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

/// The link itself, which is the whole of D5.1: the app draws no map, it
/// hands the stop to the one the driver already uses (docs/driver-app.md).
void main() {
  group('the turn-by-turn link', () {
    test('asks Google Maps to drive to the stop', () {
      expect(navigationUri(12.9716, 77.5946).toString(), 'google.navigation:q=12.9716,77.5946&mode=d');
    });

    test('keeps a southern or western stop negative', () {
      expect(navigationUri(-33.8688, -70.6693).toString(), 'google.navigation:q=-33.8688,-70.6693&mode=d');
    });
  });

  group('the fallback link', () {
    test('is an ordinary Google Maps directions URL', () {
      final url = directionsUri(12.9716, 77.5946);

      expect(url.host, 'www.google.com');
      expect(url.path, '/maps/dir/');
      expect(url.queryParameters['destination'], '12.9716,77.5946');
      expect(url.queryParameters['travelmode'], 'driving');
    });

    test('is https, because a phone without Google Maps opens it in a browser', () {
      expect(directionsUri(12.9716, 77.5946).scheme, 'https');
    });
  });
}
