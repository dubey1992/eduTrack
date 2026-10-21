import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/transport/data/models/bus_stop.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/widgets/route_builder_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_map.dart';
import '../../support/fake_transport_repository.dart';

/// Drawing a route on the school's map (docs/maps.md).
///
/// The feature is the order: tap where each stop is, in the order the bus
/// takes them, and the list beside the map is the route. Two things carry
/// the weight - that a tap lands a stop at the end of the run, and that
/// **nothing is saved until Save**, because a route half-built in the
/// database is a mess somebody has to unpick.
const _admin = AuthenticatedUser(
  id: 5,
  name: 'Admin',
  email: 'admin@example.com',
  role: UserRole.schoolAdmin,
  schoolId: 7,
);

const _school = LatLng(28.6139, 77.2090);

BusStop _place({int id = 1, String name = 'Market Square', String latitude = '28.6200000'}) {
  return BusStop(
    id: id,
    schoolId: 7,
    schoolName: 'Abbey Road School',
    name: name,
    latitude: latitude,
    longitude: '77.2100000',
    landmark: null,
    status: 'active',
    routesCount: 0,
  );
}

Widget wrap(FakeTransportRepository fake, FakeMapRenderer renderer, {LatLng? at = _school}) {
  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
      ...mapIsAvailable(renderer),
      ...mapPinsAreReady(),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: RouteBuilderMap(schoolId: 7, schoolAt: at, schoolName: 'Abbey Road School'),
      ),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Into drawing mode, where the map and the picker mean something.
Future<void> startDrawing(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('new-route')));
  await tester.pumpAndSettle();
}

/// Adds [count] of the school's existing bus stops to the run.
Future<void> addExisting(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.tap(find.byKey(const Key('add-an-existing-stop')));
    await tester.pumpAndSettle();
    // Inside the dialog: the panel's own rows are ListTiles too.
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ListTile)).first);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('before anybody starts', () {
    testWidgets('a tap on the map does nothing', (tester) async {
      // The map is for looking at until somebody says they are drawing.
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(), renderer));
      await tester.pumpAndSettle();

      expect(renderer.lastView?.onTap, isNull);
      expect(find.byKey(const Key('new-route')), findsOneWidget);
    });

    testWidgets('a school nobody has placed says so instead of offering a map', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(), FakeMapRenderer(), at: null));
      await tester.pumpAndSettle();

      expect(find.textContaining('Place this school on the map first'), findsOneWidget);
      expect(find.byKey(const Key('new-route')), findsNothing);
    });
  });

  group('drawing from the school\'s list', () {
    testWidgets('a stop can be picked from the stops the school already has', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(
        busStops: [
          _place(),
          _place(id: 2, name: 'Temple Road'),
        ],
      );
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);

      expect(find.textContaining('Tap the map to add a new stop, or pick one'), findsOneWidget);

      await addExisting(tester, 1);

      expect(find.text('Market Square'), findsOneWidget);
    });

    testWidgets('one already on the route is not offered twice', (tester) async {
      // A route passing one corner twice is a mistake the server refuses,
      // so offering it here would be offering a refusal.
      useDesktop(tester);
      final fake = FakeTransportRepository(
        busStops: [
          _place(),
          _place(id: 2, name: 'Temple Road'),
        ],
      );
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 1);

      await tester.tap(find.byKey(const Key('add-an-existing-stop')));
      await tester.pumpAndSettle();

      // Scoped to the dialog: the stop already on the run is a ListTile in
      // the panel behind it.
      Finder offered(String name) =>
          find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(ListTile, name));

      expect(offered('Market Square'), findsNothing);
      expect(offered('Temple Road'), findsOneWidget);
    });

    testWidgets('a school with no stops yet is told where they come from', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(), FakeMapRenderer()));
      await startDrawing(tester);

      await tester.tap(find.byKey(const Key('add-an-existing-stop')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tap the map to add the first one'), findsOneWidget);
    });

    testWidgets('each stop gets a pin, and the run gets a line', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository(
        busStops: [
          _place(),
          _place(id: 2, name: 'Temple Road', latitude: '28.6250000'),
        ],
      );
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await addExisting(tester, 2);

      expect(renderer.markersById.keys, containsAll(['school-7', 'draft-0', 'draft-1']));
      expect(renderer.polylines.single.points.length, 2);
    });

    testWidgets('one stop is not a line', (tester) async {
      // Two points make a run; one is a place.
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_place()]), renderer));
      await startDrawing(tester);
      await addExisting(tester, 1);

      expect(renderer.polylines, isEmpty);
    });

    testWidgets('a stop can be taken off again', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(
        busStops: [
          _place(),
          _place(id: 2, name: 'Temple Road'),
        ],
      );
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 2);

      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();

      expect(find.text('Market Square'), findsNothing);
      expect(find.text('Temple Road'), findsOneWidget);
    });

    testWidgets('and moved up the order', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository(
        busStops: [
          _place(),
          _place(id: 2, name: 'Temple Road'),
        ],
      );
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await addExisting(tester, 2);

      expect(renderer.markersById['draft-0']?.infoWindow.title, '1. Market Square');

      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();

      expect(renderer.markersById['draft-0']?.infoWindow.title, '1. Temple Road');
      expect(renderer.markersById['draft-1']?.infoWindow.title, '2. Market Square');
    });

    testWidgets('cancelling throws the sketch away', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_place()]);
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 1);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Market Square'), findsNothing);
      expect(find.byKey(const Key('new-route')), findsOneWidget);
    });
  });

  group('saving', () {
    testWidgets('the route and every call go in one request, naming their places', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(
        busStops: [
          _place(),
          _place(id: 2, name: 'Temple Road'),
        ],
      );
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 2);

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      final sent = fake.lastCall!;
      expect(sent['op'], 'createRoute');
      expect(sent['name'], 'North Loop');
      expect(sent['school_id'], 7);

      final stops = sent['stops'] as List;
      expect(stops.map((stop) => stop['bus_stop_id']).toList(), [1, 2]);
      expect(stops.map((stop) => stop['sequence_number']).toList(), [1, 2]);
      // The name and the position are the list's, so they are not sent.
      expect(stops.first.containsKey('name'), isFalse);
      expect(stops.first.containsKey('latitude'), isFalse);
    });

    testWidgets('the order on screen is the order that is sent', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(
        busStops: [
          _place(),
          _place(id: 2, name: 'Temple Road'),
        ],
      );
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 2);

      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      final stops = fake.lastCall!['stops'] as List;
      expect(stops.map((stop) => stop['bus_stop_id']).toList(), [2, 1]);
      expect(stops.map((stop) => stop['sequence_number']).toList(), [1, 2]);
    });

    testWidgets('a route with no name is refused before the server sees it', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_place()]);
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.text('Give the route a name.'), findsOneWidget);
    });

    testWidgets('a route with no stops is refused too', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least one stop'), findsOneWidget);
    });

    testWidgets("the server's complaint about a stop is shown with the stops", (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_place()]);
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 1);

      fake.failWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'stops': ['Market Square is on this route twice.'],
          },
        },
      );

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.text('Market Square is on this route twice.'), findsOneWidget);
      // The sketch survives, so somebody can fix it rather than draw the
      // whole route again.
      expect(find.text('Market Square'), findsWidgets);
    });

    testWidgets('a failure that is not about the stops is still shown', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_place()]);
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);
      await addExisting(tester, 1);

      fake.failWith = Failure.network();

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
    });
  });
}
