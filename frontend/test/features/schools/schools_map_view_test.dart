import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/maps/presentation/app_map.dart';
import 'package:edutrack_app/features/schools/data/models/school_pin.dart';
import 'package:edutrack_app/features/schools/data/school_locations_repository.dart';
import 'package:edutrack_app/features/schools/presentation/schools_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/fake_map.dart';

late List<int> opened;

SchoolPin pin({
  int id = 1,
  String name = 'Bright Future',
  double latitude = 18.5289,
  double longitude = 73.8744,
  bool isBranch = false,
  bool isActive = true,
  String city = 'Pune',
}) {
  return SchoolPin(
    id: id,
    name: name,
    latitude: latitude,
    longitude: longitude,
    isBranch: isBranch,
    isActive: isActive,
    city: city,
  );
}

List<Override> showing(SchoolLocations locations, FakeMapRenderer renderer) {
  return [
    ...mapIsAvailable(renderer),
    ...mapPinsAreReady(),
    schoolLocationsProvider.overrideWith((ref) async => locations),
  ];
}

Widget wrap(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SchoolsMapView(onOpen: opened.add)),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The schools on a map (docs/maps.md, M1d).
///
/// Which schools arrive is the server's business - the same scoping as the
/// list, so the map can never show a school the list would not. What is
/// tested here is what the screen does with them, and the two things it
/// must never do: hide a school that has no coordinates, and pretend a
/// capped map is a complete one.
void main() {
  setUp(() => opened = []);

  group('drawing the pins', () {
    testWidgets('every placed school is a pin', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final locations = SchoolLocations(
        placed: [
          pin(id: 1),
          pin(id: 2, name: 'Second', latitude: 19.07, longitude: 72.87),
        ],
        unplaced: const [],
        moreThanShown: false,
      );

      await tester.pumpWidget(wrap(showing(locations, renderer)));
      await tester.pumpAndSettle();

      expect(renderer.markersById.keys.toSet(), {'school-1', 'school-2'});
    });

    test('a school in its own right, a branch, and a school switched off are three colours', () {
      // Compared as the choice rather than as BitmapDescriptors: two
      // descriptors built the same way are not equal, so comparing them
      // passes whatever the rule does - which is how three tests here once
      // passed against a rule that had been removed.
      final school = schoolPinColour(pin());
      final branch = schoolPinColour(pin(isBranch: true));
      final closed = schoolPinColour(pin(isActive: false));

      expect({school, branch, closed}.length, 3);
    });

    test('a switched-off branch is shown as switched off, not as a branch', () {
      // Being gone is the more important of the two things to notice.
      expect(schoolPinColour(pin(isBranch: true, isActive: false)), schoolPinColour(pin(isActive: false)));
    });

    testWidgets('each pin is drawn with its own colour', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final locations = SchoolLocations(
        placed: [
          pin(id: 1),
          pin(id: 2, name: 'Branch', isBranch: true, latitude: 19.07, longitude: 72.87),
        ],
        unplaced: const [],
        moreThanShown: false,
      );

      await tester.pumpWidget(wrap(showing(locations, renderer)));
      await tester.pumpAndSettle();

      final school = renderer.markersById['school-1']!.icon;
      final branch = renderer.markersById['school-2']!.icon;

      // A drawn picture, not a hue: `defaultMarkerWithHue` does nothing on
      // the web, where the plugin converts only bitmap descriptors, so a
      // pin that asked for a hue would come out the standard red on the
      // platform this ships on first.
      expect(school, isA<BytesMapBitmap>());
      expect(branch, isA<BytesMapBitmap>());
      expect(school.toJson(), isNot(branch.toJson()));
    });
  });

  group('the schools that are not on it yet', () {
    testWidgets('they are listed, because they are the work the map prompts', (tester) async {
      useDesktop(tester);
      final locations = SchoolLocations(
        placed: [pin()],
        unplaced: const [UnplacedSchool(id: 9, name: 'Nowhere Yet')],
        moreThanShown: false,
      );

      await tester.pumpWidget(wrap(showing(locations, FakeMapRenderer())));
      await tester.pumpAndSettle();

      expect(find.text('Not on the map yet (1)'), findsOneWidget);
      expect(find.text('Nowhere Yet'), findsOneWidget);
    });

    testWidgets('they are not drawn as pins anywhere', (tester) async {
      // A school with no coordinates has no place; drawn at (0, 0) it would
      // sit off the coast of Africa and look deliberate.
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final locations = SchoolLocations(
        placed: const [],
        unplaced: const [UnplacedSchool(id: 9, name: 'Nowhere Yet')],
        moreThanShown: false,
      );

      await tester.pumpWidget(wrap(showing(locations, renderer)));
      await tester.pumpAndSettle();

      expect(renderer.markersById, isEmpty);
    });

    testWidgets('the heading is absent when every school is placed', (tester) async {
      useDesktop(tester);
      final locations = SchoolLocations(placed: [pin()], unplaced: const [], moreThanShown: false);

      await tester.pumpWidget(wrap(showing(locations, FakeMapRenderer())));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not on the map yet'), findsNothing);
    });

    testWidgets('tapping one opens it, so it can be placed', (tester) async {
      useDesktop(tester);
      final locations = SchoolLocations(
        placed: const [],
        unplaced: const [UnplacedSchool(id: 9, name: 'Nowhere Yet')],
        moreThanShown: false,
      );

      await tester.pumpWidget(wrap(showing(locations, FakeMapRenderer())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nowhere Yet'));
      await tester.pumpAndSettle();

      expect(opened, [9]);
    });
  });

  group('choosing a school', () {
    testWidgets('tapping a pin opens its card', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(
        wrap(showing(SchoolLocations(placed: [pin()], unplaced: const [], moreThanShown: false), renderer)),
      );
      await tester.pumpAndSettle();
      renderer.markersById['school-1']!.onTap!();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Card, 'Bright Future'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('tapping the same pin again closes it', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(
        wrap(showing(SchoolLocations(placed: [pin()], unplaced: const [], moreThanShown: false), renderer)),
      );
      await tester.pumpAndSettle();
      renderer.markersById['school-1']!.onTap!();
      await tester.pumpAndSettle();
      renderer.markersById['school-1']!.onTap!();
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsNothing);
    });

    testWidgets('the card says what the pin is and whether it is switched off', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final closed = pin(isBranch: true, isActive: false);

      await tester.pumpWidget(
        wrap(showing(SchoolLocations(placed: [closed], unplaced: const [], moreThanShown: false), renderer)),
      );
      await tester.pumpAndSettle();
      renderer.markersById['school-1']!.onTap!();
      await tester.pumpAndSettle();

      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Switched off'), findsOneWidget);
    });

    testWidgets('opening from the card reports the school', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(
        wrap(showing(SchoolLocations(placed: [pin(id: 7)], unplaced: const [], moreThanShown: false), renderer)),
      );
      await tester.pumpAndSettle();
      renderer.markersById['school-7']!.onTap!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(opened, [7]);
    });

    testWidgets('choosing from the list beside the map selects the same school', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();

      await tester.pumpWidget(
        wrap(showing(SchoolLocations(placed: [pin()], unplaced: const [], moreThanShown: false), renderer)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Bright Future'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Card, 'Bright Future'), findsOneWidget);
    });
  });

  group('when there are more than the map holds', () {
    testWidgets('it says so rather than quietly showing some of them', (tester) async {
      useDesktop(tester);
      final locations = SchoolLocations(placed: [pin()], unplaced: const [], moreThanShown: true);

      await tester.pumpWidget(wrap(showing(locations, FakeMapRenderer())));
      await tester.pumpAndSettle();

      expect(find.textContaining('There are more'), findsOneWidget);
    });

    testWidgets('and says nothing when every school is shown', (tester) async {
      useDesktop(tester);
      final locations = SchoolLocations(placed: [pin()], unplaced: const [], moreThanShown: false);

      await tester.pumpWidget(wrap(showing(locations, FakeMapRenderer())));
      await tester.pumpAndSettle();

      expect(find.textContaining('There are more'), findsNothing);
    });
  });

  group('when there is nothing to show', () {
    testWidgets('an empty platform says so rather than drawing an empty map', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(showing(const SchoolLocations.empty(), FakeMapRenderer())));
      await tester.pumpAndSettle();

      expect(find.textContaining('No schools yet'), findsOneWidget);
    });

    testWidgets('a failure is shown and offered a retry, not drawn as emptiness', (tester) async {
      // An empty map that should have had pins on it looks exactly like a
      // platform where nobody has placed anything.
      useDesktop(tester);
      var attempts = 0;
      final overrides = [
        ...mapIsAvailable(FakeMapRenderer()),
        schoolLocationsProvider.overrideWith((ref) async {
          attempts++;
          if (attempts == 1) throw const Failure(code: 'X', message: 'Could not reach the server.');
          return SchoolLocations(placed: [pin()], unplaced: const [], moreThanShown: false);
        }),
      ];

      await tester.pumpWidget(
        ProviderScope(
          retry: (count, error) => null,
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: SchoolsMapView(onOpen: opened.add)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Bright Future'), findsOneWidget);
    });

    testWidgets('with no map key the schools are still listed', (tester) async {
      // The list beside the map is the part that still works, and it is the
      // part somebody can act on.
      useDesktop(tester);
      final locations = SchoolLocations(
        placed: [pin()],
        unplaced: const [UnplacedSchool(id: 9, name: 'Nowhere Yet')],
        moreThanShown: false,
      );

      await tester.pumpWidget(
        wrap([...mapIsUnavailable(), schoolLocationsProvider.overrideWith((ref) async => locations)]),
      );
      await tester.pumpAndSettle();

      expect(find.text(MapUnavailable.message), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Bright Future'), findsOneWidget);
      expect(find.text('Nowhere Yet'), findsOneWidget);
    });
  });
}
