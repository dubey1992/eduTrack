import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/transport/data/models/bus_stop.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/bus_stop_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_map.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_transport_repository.dart';

/// The school's list of bus stops (docs/maps.md).
///
/// The places, not the calls. What the screen has to get right is the pair
/// a list alone cannot show: *where* each stop is, and *what would break*
/// if somebody removed it - which is why the map and the route count sit
/// beside every row.
const _admin = AuthenticatedUser(
  id: 5,
  name: 'Admin',
  email: 'admin@example.com',
  role: UserRole.schoolAdmin,
  schoolId: 1,
);

const _manager = AuthenticatedUser(
  id: 6,
  name: 'Mohan',
  email: 'mohan@example.com',
  role: UserRole.transportManager,
  schoolId: 1,
);

const _teacher = AuthenticatedUser(id: 7, name: 'Tara', email: 'tara@example.com', role: UserRole.teacher, schoolId: 1);

BusStop _stop({
  int id = 1,
  String name = 'Market Square',
  String latitude = '28.6200000',
  String longitude = '77.2100000',
  String? landmark,
  String status = 'active',
  int routesCount = 0,
}) {
  return BusStop(
    id: id,
    schoolId: 1,
    schoolName: 'Abbey Road School',
    name: name,
    latitude: latitude,
    longitude: longitude,
    landmark: landmark,
    status: status,
    routesCount: routesCount,
  );
}

/// The school these stops belong to, placed - a stop is measured against
/// where the school is, so an unplaced one has no map to draw.
School placedSchool() {
  return const School(
    id: 1,
    name: 'Abbey Road School',
    registrationNumber: 'REG-001',
    email: 'head@abbey.invalid',
    phone: '+91 9000000000',
    address: '1 Abbey Road',
    city: 'New Delhi',
    state: 'Delhi',
    country: 'India',
    postalCode: '110001',
    latitude: '28.6139000',
    longitude: '77.2090000',
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    logoUrl: null,
    status: SchoolStatus.active,
  );
}

late FakeMapRenderer renderer;

Widget wrap(FakeTransportRepository fake, {AuthenticatedUser actor = _admin}) {
  renderer = FakeMapRenderer();

  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: [placedSchool()])),
      ...mapIsAvailable(renderer),
      ...mapPinsAreReady(),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: BusStopListScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('it lists the stops and puts each one on the map', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        FakeTransportRepository(
          busStops: [
            _stop(),
            _stop(id: 2, name: 'Temple Road'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Market Square'), findsOneWidget);
    expect(find.text('Temple Road'), findsOneWidget);
    expect(renderer.markersById.keys, containsAll(['bus-stop-1', 'bus-stop-2']));
  });

  testWidgets('no stops yet says so', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeTransportRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No bus stops yet.'), findsOneWidget);
  });

  testWidgets('a failure shows its message with a retry', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeTransportRepository()..failWith = Failure.network()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });

  group('what every row says', () {
    testWidgets('a stop no route uses says so', (tester) async {
      // It is what decides whether the stop can be removed at all.
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop()])));
      await tester.pumpAndSettle();

      expect(find.textContaining('On no routes'), findsOneWidget);
    });

    testWidgets('a stop routes call at says how many', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop(routesCount: 3)])));
      await tester.pumpAndSettle();

      expect(find.textContaining('On 3 routes'), findsOneWidget);
    });

    testWidgets('one route is said in the singular', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop(routesCount: 1)])));
      await tester.pumpAndSettle();

      expect(find.textContaining('On 1 route'), findsOneWidget);
      expect(find.textContaining('On 1 routes'), findsNothing);
    });

    testWidgets('a landmark is shown beside it', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop(landmark: 'Opposite the post office')])));
      await tester.pumpAndSettle();

      expect(find.textContaining('Opposite the post office'), findsOneWidget);
    });

    testWidgets('a retired stop is badged', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop(status: 'inactive')])));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'Inactive'), findsOneWidget);
    });
  });

  group('adding one', () {
    testWidgets('tapping the map opens the form where you tapped', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop()])));
      await tester.pumpAndSettle();

      renderer.tapAt(const LatLng(28.63, 77.22));
      await tester.pumpAndSettle();

      expect(find.text('Add Bus Stop'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '28.6300000'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '77.2200000'), findsOneWidget);
    });

    testWidgets('the button opens the same form with nothing filled in', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop()])));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-bus-stop')));
      await tester.pumpAndSettle();

      expect(find.text('Add Bus Stop'), findsOneWidget);
    });

    testWidgets('a stop with no name is refused before the server sees it', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_stop()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      renderer.tapAt(const LatLng(28.63, 77.22));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets('naming it and saving sends the place that was tapped', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_stop()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      renderer.tapAt(const LatLng(28.63, 77.22));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Stop name'), 'Temple Road');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {
        'op': 'createBusStop',
        'school_id': null,
        'name': 'Temple Road',
        'latitude': '28.6300000',
        'longitude': '77.2200000',
        'landmark': null,
      });
    });

    testWidgets("the server's complaint lands under the box it names", (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_stop()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      renderer.tapAt(const LatLng(28.63, 77.22));
      await tester.pumpAndSettle();

      // Only the save fails: the list behind it loaded fine, which is the
      // situation somebody is actually in when they hit a clash.
      fake.failWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'name': ['The name has already been taken.'],
          },
        },
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Stop name'), 'Market Square');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('The name has already been taken.'), findsOneWidget);
    });
  });

  group('removing one', () {
    testWidgets('a stop nothing uses says nothing else changes', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop()])));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(find.textContaining('nothing else changes'), findsOneWidget);
    });

    testWidgets('a stop routes call at warns before anybody presses it', (tester) async {
      // The server refuses it anyway; being told first is the difference
      // between a dialog and a dead end.
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop(routesCount: 2)])));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is on 2 routes'), findsOneWidget);
      expect(find.textContaining('make it inactive instead'), findsOneWidget);
    });

    testWidgets('confirming removes it', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository(busStops: [_stop()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {'op': 'deleteBusStop', 'id': 1});
    });
  });

  group('who may keep the list', () {
    testWidgets('a transport manager keeps it', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop()]), actor: _manager));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-bus-stop')), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
    });

    testWidgets('a teacher reads it and changes nothing', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(busStops: [_stop()]), actor: _teacher));
      await tester.pumpAndSettle();

      expect(find.text('Market Square'), findsOneWidget);
      expect(find.byKey(const Key('add-bus-stop')), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      // And a tap on the map does nothing, rather than opening a form that
      // would be refused.
      expect(renderer.lastView?.onTap, isNull);
    });
  });

  testWidgets('searching asks the server', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(
      busStops: [
        _stop(),
        _stop(id: 2, name: 'Temple Road'),
      ],
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Search stops'), 'temple');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(fake.lastBusStopQuery, 'temple');
  });

  group('where the map centres', () {
    testWidgets('on the school, read off the page rather than the schools list', (tester) async {
      // A transport manager cannot read /schools at all, so the page
      // carrying it is the only way this screen learns where to look.
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(), actor: _manager));
      await tester.pumpAndSettle();

      expect(renderer.lastView?.centre.latitude, closeTo(28.6139, 0.0001));
    });

    testWidgets('no single school says so instead of drawing a map of nowhere', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository()..schoolAt = null));
      await tester.pumpAndSettle();

      expect(find.textContaining('Place the school on the map first'), findsOneWidget);
    });
  });
}
