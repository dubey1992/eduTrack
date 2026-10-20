import 'dart:io';

import 'package:edutrack_app/features/maps/data/polyline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Google's encoded polyline, back into points (docs/maps.md, M2).
///
/// The other half of `school/gateways/google_maps.py`, which encodes it.
/// **Anything this cannot read is no line at all**: a half-decoded polyline
/// is a road that goes somewhere the bus does not, which is worse than
/// falling back to straight lines between the stops.
void main() {
  group('a polyline Google sent', () {
    test('it decodes the sample from Google\'s own documentation', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.00001));
      expect(points[0].longitude, closeTo(-120.2, 0.00001));
      expect(points[2].latitude, closeTo(43.252, 0.00001));
      expect(points[2].longitude, closeTo(-126.453, 0.00001));
    });

    test('a single point is a line of one', () {
      final points = decodePolyline('_p~iF~ps|U');

      expect(points, hasLength(1));
    });

    test('a road that runs south and west keeps going south and west', () {
      // Three points down the route Google drew for the demo school, each
      // step negative in both halves. Encoded by the server's own encoder.
      final points = decodePolyline('ihbpBufvaM|_@n`@z_BdcG');

      expect(points, hasLength(3));
      expect(points[1].latitude, lessThan(points[0].latitude));
      expect(points[1].longitude, lessThan(points[0].longitude));
      expect(points[2].latitude, closeTo(18.51, 0.00001));
      expect(points[2].longitude, closeTo(73.8, 0.00001));
    });

    test('a step of one hundred-thousandth south-west is still south-west', () {
      // The smallest negative step there is, and the one that broke on the
      // web: an odd number of zero, whose sign is undone by a bitwise
      // complement that means something different there.
      final points = decodePolyline('??@@');

      expect(points, hasLength(2));
      expect(points[1].latitude, closeTo(-0.00001, 0.000001));
      expect(points[1].longitude, closeTo(-0.00001, 0.000001));
    });

    test('it keeps five decimal places, which is about a metre', () {
      final points = decodePolyline('_p~iF~ps|U');

      expect(points.single.latitude, closeTo(38.5, 0.000001));
    });
  });

  group('a polyline it cannot read', () {
    test('nothing at all is no line', () {
      expect(decodePolyline(null), isEmpty);
      expect(decodePolyline(''), isEmpty);
    });

    test('a chunk that never ends is no line, not a hang', () {
      // Every byte has the continuation bit set, so the stream never
      // completes a number.
      expect(decodePolyline('~~~~~~~~~~~~~~~~~~~~~~~~'), isEmpty);
    });

    test('a stream that stops mid-number is no line', () {
      expect(decodePolyline('_p~iF~ps'), isEmpty);
    });

    test('characters below the encoding range are no line', () {
      expect(decodePolyline('!!!!'), isEmpty);
    });

    test('a point off the earth is no line', () {
      // Latitudes that keep climbing past the pole. Checked before the
      // LatLng is built, because its constructor clamps into range - a
      // reading of 180 degrees north would otherwise arrive as a perfectly
      // ordinary 90 and look like a real place.
      // Encoded by the server's own encoder from (100, 10) and (10, 200) -
      // places that do not exist.
      expect(decodePolyline('_gjaR_c`|@'), isEmpty);
      expect(decodePolyline('_c`|@_ouce@'), isEmpty);

      // And the same encoder's answer for a real place still decodes.
      expect(decodePolyline('_h|oB_amaM'), hasLength(1));
    });

    test('it never asks a bitwise complement what a negative number is', () {
      // Not a test of behaviour but of the source, because no test run on
      // the Dart VM can catch this one: to a bitwise operator on the web an
      // int is 32 bits unsigned, so `~0` is 4294967295 rather than -1. Every
      // southward or westward step of a road decoded as a point off the
      // earth, this file refused the whole line, and the map drew no road at
      // all - while every test here passed.
      //
      // This is the only bitwise arithmetic in the application, so one
      // reading of one file covers it.
      final source = File('lib/features/maps/data/polyline.dart').readAsStringSync();
      final code = source.split('\n').where((line) => !line.trimLeft().startsWith('//')).join('\n');

      expect(code, isNot(contains('~')), reason: 'use arithmetic that means the same on both platforms');
    });

    test('nothing it refuses is half a line', () {
      // The point of returning nothing rather than what it managed: a road
      // that goes somewhere the bus does not is worse than no road.
      for (final broken in ['~~~~', '_p~iF~ps', '!!!!']) {
        expect(decodePolyline(broken), isEmpty, reason: broken);
      }
    });
  });
}
