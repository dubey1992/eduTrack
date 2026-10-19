import 'dart:async';

import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/maps/data/places_repository.dart';
import 'package:edutrack_app/features/maps/presentation/app_map.dart';
import 'package:edutrack_app/features/maps/presentation/location_picker.dart';
import 'package:edutrack_app/features/schools/presentation/widgets/coordinates_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/fake_map.dart';
import '../../support/fake_places_repository.dart';

late TextEditingController latitude;
late TextEditingController longitude;

const station = PlaceSuggestion(placeId: 'ChIJ_station', label: 'Station Road', detail: 'Pune, Maharashtra, India');

const stationItself = FoundPlace(
  label: 'Station Road',
  address: 'Station Rd, Pune, Maharashtra 411001, India',
  latitude: 18.5289,
  longitude: 73.8744,
);

Widget wrap(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LocationPicker(
            latitude: latitude,
            longitude: longitude,
            child: CoordinatesFields(latitude: latitude, longitude: longitude),
          ),
        ),
      ),
    ),
  );
}

List<Override> withMap(FakeMapRenderer renderer, FakePlacesRepository places) {
  return [...mapIsAvailable(renderer), placesRepositoryProvider.overrideWithValue(places)];
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A suggestion in the dropped-down list - not the same words sitting in
/// the search box above it, which `find.text` would also match.
Finder suggestion(String label) => find.widgetWithText(ListTile, label);

Future<void> typeSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.widgetWithText(TextField, 'Search for an address'), text);
  // The search is debounced: nobody means the word they are halfway through.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

/// Putting a school on the map (docs/maps.md, M1).
///
/// Three ways to set the same pair of numbers, because the people doing it
/// have different things to hand: an address, a corner of a map, or the
/// coordinates already. **The boxes are the source of truth** - they are
/// what the form sends and what still works with no map at all.
void main() {
  setUp(() {
    latitude = TextEditingController();
    longitude = TextEditingController();
  });

  tearDown(() {
    latitude.dispose();
    longitude.dispose();
  });

  group('searching for an address', () {
    testWidgets('it offers what Google suggested', (tester) async {
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: [station]);

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'Station Road');

      expect(suggestion('Station Road'), findsOneWidget);
      expect(find.text('Pune, Maharashtra, India'), findsOneWidget);
    });

    testWidgets('it waits for somebody to stop typing', (tester) async {
      // Google charges per search, and nobody means "Stat".
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: [station]);

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Search for an address'), 'Stat');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.widgetWithText(TextField, 'Search for an address'), 'Station Road');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(places.searches, 1);
      expect(places.lastQuery, 'Station Road');
    });

    testWidgets('two characters are not worth asking about', (tester) async {
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: [station]);

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'St');

      expect(places.searches, 0);
    });

    testWidgets('picking one fills the boxes in', (tester) async {
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: [station], place: stationItself);

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'Station Road');
      await tester.tap(suggestion('Station Road'));
      await tester.pumpAndSettle();

      expect(double.parse(latitude.text), closeTo(18.5289, 0.0001));
      expect(double.parse(longitude.text), closeTo(73.8744, 0.0001));
    });

    testWidgets('picking one drops the pin there', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final places = FakePlacesRepository(suggestions: [station], place: stationItself);

      await tester.pumpWidget(wrap(withMap(renderer, places)));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'Station Road');
      await tester.tap(suggestion('Station Road'));
      await tester.pumpAndSettle();

      final pin = renderer.markersById['picked']!;
      expect(pin.position.latitude, closeTo(18.5289, 0.0001));
    });

    testWidgets('a lookup that failed leaves the pin where it was', (tester) async {
      // Moving it somewhere nobody chose would be worse than not moving it.
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: [station], place: null);
      latitude.text = '19.0760';
      longitude.text = '72.8777';

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'Station Road');
      await tester.tap(suggestion('Station Road'));
      await tester.pumpAndSettle();

      expect(latitude.text, '19.0760');
    });

    testWidgets('the search is biased towards the pin already placed', (tester) async {
      // "Station Road" means a different road in every city.
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: [station]);
      latitude.text = '19.0760';
      longitude.text = '72.8777';

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'Station Road');

      expect(places.lastNearLatitude, closeTo(19.0760, 0.0001));
    });

    testWidgets('a search that found nothing is not an error', (tester) async {
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: const []);

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'Nowhere At All');

      expect(tester.takeException(), isNull);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('it says it is searching', (tester) async {
      useDesktop(tester);
      final places = FakePlacesRepository(suggestions: [station])..searchGate = Completer<void>();

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), places)));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Search for an address'), 'Station Road');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      places.searchGate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('clicking the map', () {
    testWidgets('it drops a pin and fills the boxes in', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(withMap(renderer, FakePlacesRepository())));
      await tester.pumpAndSettle();
      renderer.tapAt(const LatLng(18.5289, 73.8744));
      await tester.pumpAndSettle();

      expect(double.parse(latitude.text), closeTo(18.5289, 0.0001));
      expect(renderer.markersById.containsKey('picked'), isTrue);
    });

    testWidgets('it says what was clicked on', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final places = FakePlacesRepository(address: 'Station Rd, Pune, Maharashtra 411001, India');

      await tester.pumpWidget(wrap(withMap(renderer, places)));
      await tester.pumpAndSettle();
      renderer.tapAt(const LatLng(18.5289, 73.8744));
      await tester.pumpAndSettle();

      expect(find.text('Station Rd, Pune, Maharashtra 411001, India'), findsOneWidget);
    });

    testWidgets('a point with no address is still a point', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(withMap(renderer, FakePlacesRepository(address: ''))));
      await tester.pumpAndSettle();
      renderer.tapAt(const LatLng(0.5, -30.2));
      await tester.pumpAndSettle();

      expect(double.parse(latitude.text), closeTo(0.5, 0.0001));
      expect(find.text('Drag the pin to adjust it.'), findsOneWidget);
    });

    testWidgets('the pin can be dragged', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(withMap(renderer, FakePlacesRepository())));
      await tester.pumpAndSettle();
      renderer.tapAt(const LatLng(18.5289, 73.8744));
      await tester.pumpAndSettle();

      final pin = renderer.markersById['picked']!;
      expect(pin.draggable, isTrue);

      pin.onDragEnd!(const LatLng(18.6000, 73.9000));
      await tester.pumpAndSettle();

      expect(double.parse(latitude.text), closeTo(18.6, 0.0001));
    });
  });

  group('typing the numbers in', () {
    testWidgets('it moves the pin, so the two never disagree', (tester) async {
      // Somebody migrating from a spreadsheet has the coordinates already.
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(withMap(renderer, FakePlacesRepository())));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '18.5289');
      await tester.enterText(find.widgetWithText(TextFormField, 'Longitude (optional)'), '73.8744');
      await tester.pumpAndSettle();

      expect(renderer.markersById['picked']!.position.latitude, closeTo(18.5289, 0.0001));
    });

    testWidgets('half a coordinate is no pin at all', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(withMap(renderer, FakePlacesRepository())));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '18.5289');
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('picked'), isFalse);
    });

    testWidgets('a number off the earth is no pin at all', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(withMap(renderer, FakePlacesRepository())));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '91');
      await tester.enterText(find.widgetWithText(TextFormField, 'Longitude (optional)'), '73.8744');
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('picked'), isFalse);
    });
  });

  group('removing the pin', () {
    testWidgets('it clears both boxes', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(wrap(withMap(renderer, FakePlacesRepository())));
      await tester.pumpAndSettle();
      renderer.tapAt(const LatLng(18.5289, 73.8744));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove pin'));
      await tester.pumpAndSettle();

      expect(latitude.text, isEmpty);
      expect(longitude.text, isEmpty);
      expect(renderer.markersById.containsKey('picked'), isFalse);
    });

    testWidgets('there is nothing to remove until something is placed', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(withMap(FakeMapRenderer(), FakePlacesRepository())));
      await tester.pumpAndSettle();

      expect(find.text('Remove pin'), findsNothing);
    });
  });

  group('with no map', () {
    testWidgets('the boxes still work, because they are what the form sends', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap([...mapIsUnavailable(), placesRepositoryProvider.overrideWithValue(FakePlacesRepository())]),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Latitude (optional)'), '18.5289');
      await tester.pumpAndSettle();

      expect(find.text(MapUnavailable.message), findsOneWidget);
      expect(latitude.text, '18.5289');
    });
  });
}
