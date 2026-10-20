import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Google's encoded polyline format, back into points (docs/maps.md, M2).
///
/// The server stores the road as Google encoded it and sends it on
/// unchanged, so this is the other half of `school/gateways/google_maps.py`.
/// Decoding here rather than sending a list of points keeps the answer
/// small: a route of a few hundred points is a line of text instead of a
/// few hundred objects.
///
/// **Anything it cannot read is no line at all.** A half-decoded polyline
/// is a road that goes somewhere the bus does not, which is worse than
/// falling back to straight lines between the stops.
List<LatLng> decodePolyline(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];

  final points = <LatLng>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  while (index < encoded.length) {
    for (final isLatitude in const [true, false]) {
      var result = 0;
      var shift = 0;
      var byte = 0;

      do {
        if (index >= encoded.length) return const [];

        byte = encoded.codeUnitAt(index) - 63;
        index++;

        if (byte < 0) return const [];

        // Six chunks hold any coordinate on earth: 180 degrees at five
        // decimal places needs 26 bits, and six chunks carry 30. A seventh
        // is either corruption or an attempt to shift for as long as it
        // likes - and on the web, where bitwise work is 32 bits wide, a
        // shift that far silently wraps and turns nonsense into a
        // plausible-looking place. Checked before the shift, not after.
        if (shift > 25) return const [];

        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);

      // Google's odd numbers are negative, which its own documentation
      // undoes with `~(result >> 1)`. Written out as arithmetic instead,
      // because `~` does not mean the same thing on both platforms: on the
      // web an int is a 32-bit unsigned quantity to a bitwise operator, so
      // `~0` is 4294967295 rather than -1, and every southward or westward
      // step of the road became a point off the earth.
      final delta = (result & 1) != 0 ? -((result + 1) >> 1) : result >> 1;

      if (isLatitude) {
        latitude += delta;
      } else {
        longitude += delta;
      }
    }

    final degreesLat = latitude / 1e5;
    final degreesLng = longitude / 1e5;

    // Checked before the LatLng is built, not after: its constructor clamps
    // latitude into range, so a reading of 180 degrees north arrives as a
    // perfectly ordinary 90 and the check would never fire.
    //
    // Off the earth means the stream has gone wrong; the rest of it will be
    // wrong too, because every point is an offset from this one.
    if (degreesLat.abs() > 90 || degreesLng.abs() > 180) return const [];

    points.add(LatLng(degreesLat, degreesLng));
  }

  return points;
}
