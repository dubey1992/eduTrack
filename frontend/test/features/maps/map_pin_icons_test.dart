import 'package:edutrack_app/features/maps/presentation/map_pin_icons.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins drawn rather than asked for by hue (docs/maps.md, M1d).
///
/// This exists because of a gap that no test found and driving the app did:
/// `BitmapDescriptor.defaultMarkerWithHue` does nothing on the web.
/// `google_maps_flutter_web` converts only bitmap descriptors, so a default
/// marker with a hue falls through its switch and every pin comes out the
/// standard red - on Android the same code is correctly coloured, so it
/// looks right on a phone and is flat on the platform shipped first.
void main() {
  testWidgets('a pin is a bitmap, which both platforms understand', (tester) async {
    // Through runAsync: drawing a pin rasterises a canvas and encodes a
    // PNG, which is real asynchronous work that the fake clock inside
    // testWidgets never allows to finish.
    final pin = await tester.runAsync(() => drawPin(const Color(0xFFDC2626)));

    expect(pin, isA<BytesMapBitmap>());
  });

  testWidgets('two colours are two different pictures', (tester) async {
    final red = await tester.runAsync(() => drawPin(const Color(0xFFDC2626)));
    final blue = await tester.runAsync(() => drawPin(const Color(0xFF0EA5E9)));

    expect(red!.toJson(), isNot(blue!.toJson()));
  });

  testWidgets('the same colour draws the same picture', (tester) async {
    // Otherwise every rebuild would be a new bitmap, and Google would be
    // handed a fresh image per pin per frame.
    final once = await tester.runAsync(() => drawPin(const Color(0xFFDC2626)));
    final again = await tester.runAsync(() => drawPin(const Color(0xFFDC2626)));

    expect(once!.toJson(), again!.toJson());
  });

  testWidgets('it is sized for the screen rather than left as raw pixels', (tester) async {
    // A 96-pixel bitmap handed over without a width is drawn 96 *logical*
    // pixels across, which is an enormous pin.
    final pin = await tester.runAsync(() => drawPin(const Color(0xFFDC2626), size: 96));

    expect((pin! as BytesMapBitmap).width, 48);
  });

  testWidgets('every colour the map uses can be drawn', (tester) async {
    for (final colour in MapPinColour.values) {
      final pin = await tester.runAsync(() => drawPin(colour.colour));

      expect(pin, isA<BytesMapBitmap>(), reason: colour.name);
    }
  });

  testWidgets('the bus is a disc, and every place is a pin', (tester) async {
    // Shape, not colour: a bus that has gone quiet is pale grey and a stop
    // already reached is grey, and on a route where the bus has just left a
    // stop those two sit on top of each other.
    final disc = await tester.runAsync(() => drawDisc(MapPinColour.bus.colour));
    final pin = await tester.runAsync(() => drawPin(MapPinColour.bus.colour));

    expect((disc! as BytesMapBitmap).byteData, isNot((pin! as BytesMapBitmap).byteData));
  });

  test('the bus colours are the ones drawn as discs, and nothing else is', () {
    expect(MapPinColour.values.where((colour) => colour.isTheBus).toSet(), {MapPinColour.bus, MapPinColour.busStale});
  });

  test('no two of them are the same colour', () {
    expect({for (final colour in MapPinColour.values) colour.colour}.length, MapPinColour.values.length);
  });
}
