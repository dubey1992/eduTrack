import 'dart:async';

import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/maps/data/maps_config.dart';
import 'package:edutrack_app/features/maps/presentation/app_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/fake_map.dart';

const _somewhere = AppMapView(centre: LatLng(18.5289, 73.8744));

Widget wrap(List<Override> overrides, {AppMapView view = _somewhere}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: AppMap(view: view, height: 300)),
    ),
  );
}

/// The map widget every screen draws through (docs/maps.md, M1).
///
/// The rule the whole thing rests on: **a map is an improvement on a screen,
/// never the screen itself.** No key, a refused key, an ad blocker, Google
/// down - each says so in the space the map would have taken, and the list
/// the map was illustrating carries on beside it.
void main() {
  group('when a map can be drawn', () {
    testWidgets('it draws one', (tester) async {
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(mapIsAvailable(renderer)));
      await tester.pumpAndSettle();

      expect(renderer.builds, 1);
      expect(find.text(MapUnavailable.message), findsNothing);
    });

    testWidgets('it is given the centre and the pins the screen asked for', (tester) async {
      final renderer = FakeMapRenderer();
      // Not const: a Marker has no primitive equality, so it cannot sit in
      // a constant set.
      final view = AppMapView(
        centre: const LatLng(18.5289, 73.8744),
        zoom: 11,
        markers: {const Marker(markerId: MarkerId('school-4'), position: LatLng(18.5, 73.8))},
      );

      await tester.pumpWidget(wrap(mapIsAvailable(renderer), view: view));
      await tester.pumpAndSettle();

      expect(renderer.lastView!.centre.latitude, closeTo(18.5289, 0.0001));
      expect(renderer.lastView!.zoom, 11);
      expect(renderer.markersById.keys, ['school-4']);
    });

    testWidgets('a click on the map reaches the screen', (tester) async {
      final renderer = FakeMapRenderer();
      LatLng? clicked;

      await tester.pumpWidget(
        wrap(
          mapIsAvailable(renderer),
          view: AppMapView(centre: const LatLng(18.5, 73.8), onTap: (position) => clicked = position),
        ),
      );
      await tester.pumpAndSettle();
      renderer.tapAt(const LatLng(19.1, 72.9));

      expect(clicked!.latitude, closeTo(19.1, 0.0001));
    });
  });

  group('when it cannot', () {
    testWidgets('no key says so plainly rather than showing a broken frame', (tester) async {
      await tester.pumpWidget(wrap(mapIsUnavailable()));
      await tester.pumpAndSettle();

      expect(find.text(MapUnavailable.message), findsOneWidget);
    });

    testWidgets('a key that is there but empty is no key', (tester) async {
      final overrides = [
        // Built the only way the app builds one, because the constructor
        // cannot express "available with no key" any more.
        mapsConfigProvider.overrideWith((ref) async => MapsConfig.fromJson({'available': true, 'browser_key': '  '})),
      ];

      await tester.pumpWidget(wrap(overrides));
      await tester.pumpAndSettle();

      expect(find.text(MapUnavailable.message), findsOneWidget);
    });

    testWidgets('a request that failed is the same as having no key', (tester) async {
      // The repository never throws, so this is the belt to its braces: a
      // provider error must still leave a sentence rather than a red box.
      final overrides = [mapsConfigProvider.overrideWith((ref) async => throw StateError('no'))];

      await tester.pumpWidget(wrap(overrides));
      await tester.pumpAndSettle();

      expect(find.text(MapUnavailable.message), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the map is never asked to draw itself without a key', (tester) async {
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap([...mapIsUnavailable(), mapRendererProvider.overrideWithValue(renderer)]));
      await tester.pumpAndSettle();

      expect(renderer.builds, 0);
    });
  });

  group('while it is still being worked out', () {
    testWidgets('it waits rather than flashing "unavailable"', (tester) async {
      // Saying there is no map and then drawing one is worse than a pause:
      // an administrator reads the sentence and goes looking for a setting.
      final gate = Completer<MapsConfig>();
      final overrides = [
        mapRendererProvider.overrideWithValue(FakeMapRenderer()),
        mapsConfigProvider.overrideWith((ref) => gate.future),
      ];

      await tester.pumpWidget(wrap(overrides));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(MapUnavailable.message), findsNothing);

      gate.complete(const MapsConfig.withKey('k'));
      await tester.pumpAndSettle();
    });
  });

  group('what the server said', () {
    test('a key and the word yes is a map', () {
      final config = MapsConfig.fromJson({'available': true, 'browser_key': 'AIza-test'});

      expect(config.available, isTrue);
      expect(config.browserKey, 'AIza-test');
    });

    test('yes without a key is not a map', () {
      expect(MapsConfig.fromJson({'available': true, 'browser_key': ''}).available, isFalse);
    });

    test('no is not a map, whatever else is in the envelope', () {
      expect(MapsConfig.fromJson({'available': false, 'browser_key': 'AIza-test'}).available, isFalse);
    });

    test('a shape nobody expected is not a map, and not a crash', () {
      for (final body in <Map<String, dynamic>>[
        {},
        {'available': 'yes', 'browser_key': 42},
        {'browser_key': null},
      ]) {
        expect(MapsConfig.fromJson(body).available, isFalse, reason: '$body');
      }
    });
  });
}
