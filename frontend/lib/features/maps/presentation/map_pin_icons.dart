import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Pins drawn here rather than asked for by hue (docs/maps.md, M1d).
///
/// **`BitmapDescriptor.defaultMarkerWithHue` does nothing on the web.**
/// `google_maps_flutter_web` converts only bitmap descriptors; a default
/// marker with a hue falls through its switch and every pin comes out the
/// standard red. On Android the hue is honoured, so a map coloured that way
/// looks right in testing on a phone and is flat on the web build the
/// product ships first.
///
/// So the pins are drawn into a bitmap, which both platforms understand.
/// Four of them, built once and held: a marker rebuilt per frame would
/// redraw and re-encode a PNG for every pin on every pan.
///
/// The colours are named by what they do on a map rather than by what they
/// stand for, because three maps now use them for three different things -
/// a school, a stop on a route, a stop on a trip - and the screen that
/// draws the pins is where the meaning belongs.
enum MapPinColour {
  /// The one thing on the map everything else is arranged around: a school
  /// in its own right, or the school a route runs to.
  primary(Color(0xFFDC2626)),

  /// An ordinary member of the set: a branch, or a stop still to come.
  secondary(Color(0xFF0EA5E9)),

  /// The thing most worth noticing - a school switched off, or the stop the
  /// bus is heading for next.
  muted(Color(0xFFF59E0B)),

  /// Behind it rather than ahead of it: a stop the trip has already
  /// reached. Still drawn, because where the bus has been is part of
  /// reading where it is.
  done(Color(0xFF64748B));

  const MapPinColour(this.colour);

  final Color colour;
}

/// The drawn pins, one per colour. Null while they are still being drawn -
/// the map shows Google's own markers until then rather than no pins.
final mapPinIconsProvider = FutureProvider<Map<MapPinColour, BitmapDescriptor>>((ref) async {
  return {for (final colour in MapPinColour.values) colour: await drawPin(colour.colour)};
});

/// The classic map pin: a circle with a tail, a white ring around it so it
/// reads against both the pale land and the dark water, and a hole in the
/// middle so overlapping pins can still be told apart.
Future<BitmapDescriptor> drawPin(Color colour, {double size = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

  final centre = Offset(size / 2, size * 0.38);
  final radius = size * 0.30;

  final body = Paint()
    ..color = colour
    ..isAntiAlias = true;
  final ring = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = size * 0.07
    ..isAntiAlias = true;

  // The tail, drawn first so the circle covers where it joins.
  final tail = Path()
    ..moveTo(centre.dx - radius * 0.62, centre.dy + radius * 0.60)
    ..lineTo(centre.dx, size * 0.97)
    ..lineTo(centre.dx + radius * 0.62, centre.dy + radius * 0.60)
    ..close();

  canvas
    ..drawPath(tail, body)
    ..drawCircle(centre, radius, body)
    ..drawCircle(centre, radius, ring)
    ..drawCircle(centre, radius * 0.34, Paint()..color = Colors.white);

  final image = await recorder.endRecording().toImage(size.round(), size.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  // `width` tells Google how big to draw it whatever the device pixel
  // ratio; without it a 96px bitmap is a 96 *logical* pixel pin, which is
  // enormous.
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: size / 2);
}
