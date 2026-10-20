import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/maps/presentation/map_pin_icons.dart';
import 'package:edutrack_app/features/transport/data/models/transport_route.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:edutrack_app/features/transport/data/models/trip_live_location.dart';
import 'package:edutrack_app/features/transport/presentation/widgets/trip_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';

import '../../support/fake_map.dart';
import '../../support/fake_transport_repository.dart';

/// Google's own documented sample, which decodes to three points.
const aRoad = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

TripStop stop({
  int id = 1,
  int sequence = 1,
  String name = 'Lake View',
  bool reached = false,
  String? latitude = '18.5000000',
  String? longitude = '73.8000000',
}) {
  return TripStop(
    id: id,
    name: name,
    sequenceNumber: sequence,
    pickupTime: null,
    dropTime: null,
    reached: reached,
    latitude: latitude,
    longitude: longitude,
  );
}

TransportTrip trip({
  List<TripStop> stops = const [],
  TripStatus status = TripStatus.inProgress,
  String? schoolLatitude = '18.5289000',
  String? schoolLongitude = '73.8744000',
  RoutePath path = const RoutePath.notComputed(),
}) {
  return TransportTrip(
    id: 7,
    schoolId: 1,
    routeId: 1,
    routeName: 'Green Park',
    routeLabel: 'Bus 04 - Green Park',
    vehicleId: 1,
    vehicleName: 'Bus 04',
    vehicleRegistrationNumber: 'MH 12 AB 1234',
    driverId: 1,
    driverName: 'Sanjay Patel',
    driverMobile: null,
    tripDate: '2026-09-09',
    direction: TripDirection.pickup,
    status: status,
    currentStopId: null,
    currentStopName: null,
    startedByName: null,
    startedAt: '2026-09-09T07:30:00Z',
    endedAt: null,
    ridersCount: 3,
    stops: stops,
    schoolLatitude: schoolLatitude,
    schoolLongitude: schoolLongitude,
    path: path,
  );
}

BusPosition bus({
  String latitude = '18.5200000',
  String longitude = '73.8300000',
  int ageSeconds = 20,
  bool isStale = false,
}) {
  return BusPosition(
    latitude: latitude,
    longitude: longitude,
    accuracyM: 12,
    speedMps: 8,
    heading: 90,
    recordedAt: '2026-09-09T07:35:00Z',
    ageSeconds: ageSeconds,
    isStale: isStale,
  );
}

late FakeMapRenderer renderer;

Widget wrap(TransportTrip given, {BusPosition? at, int? eta}) {
  renderer = FakeMapRenderer();

  return ProviderScope(
    overrides: [...mapIsAvailable(renderer), ...mapPinsAreReady()],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TripMap(trip: given, bus: at, etaSeconds: eta),
        ),
      ),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A trip's road, school and stops (docs/maps.md, M3).
///
/// The rule it is built around: **this is drawn from the stop marks the
/// trip already records, never from the bus.** A trip that finished last
/// week reads exactly like one running now, and a trip whose attendant
/// never shared a position still shows where it went.
void main() {
  group('which stop is next', () {
    test('it is the first one not reached yet', () {
      final running = trip(
        stops: [stop(id: 1, sequence: 1, reached: true), stop(id: 2, sequence: 2), stop(id: 3, sequence: 3)],
      );

      expect(nextStop(running)?.id, 2);
    });

    test('a trip with every stop reached is heading nowhere', () {
      final running = trip(stops: [stop(id: 1, reached: true), stop(id: 2, sequence: 2, reached: true)]);

      expect(nextStop(running), isNull);
    });

    test('a finished trip has no next stop, even with stops left unreached', () {
      // Trips do end this way. Drawing one of them as "next" would say the
      // bus is still on its way there, which it is not.
      final done = trip(status: TripStatus.completed, stops: [stop(id: 1, reached: true), stop(id: 2, sequence: 2)]);

      expect(nextStop(done), isNull);
    });

    test('a cancelled trip has no next stop either', () {
      final gone = trip(status: TripStatus.cancelled, stops: [stop(id: 1)]);

      expect(nextStop(gone), isNull);
    });
  });

  group('what colour a stop is', () {
    // Read through the rule rather than the marker: a BitmapDescriptor has
    // no value equality, so comparing two markers' icons would pass
    // whatever this says.
    test('reached is behind it', () {
      expect(stopPinColour(stop(reached: true), null), MapPinColour.done);
    });

    test('the next one is the one worth noticing', () {
      final next = stop(id: 2, sequence: 2);

      expect(stopPinColour(next, next), MapPinColour.muted);
    });

    test('the rest are ordinary', () {
      expect(stopPinColour(stop(id: 3, sequence: 3), stop(id: 2, sequence: 2)), MapPinColour.secondary);
    });

    test('reached wins over next, so one stop is never two things', () {
      // Cannot arise from nextStop, which skips reached stops - but the two
      // rules are separate and only this keeps them in order.
      final odd = stop(id: 2, reached: true);

      expect(stopPinColour(odd, odd), MapPinColour.done);
    });

    test('the words match the colours', () {
      final next = stop(id: 2, sequence: 2);

      expect(stopStateLabel(stop(reached: true), next), 'Reached');
      expect(stopStateLabel(next, next), 'Next stop');
      expect(stopStateLabel(stop(id: 3, sequence: 3), next), 'Still to come');
    });
  });

  group('the pins on the map', () {
    testWidgets('a pin per placed stop, and one for the school', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [
              stop(id: 1),
              stop(id: 2, sequence: 2, name: 'Central Park'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById.keys, containsAll(<String>['stop-1', 'stop-2', 'school']));
    });

    testWidgets('a stop nobody has placed is not a pin', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(trip(stops: [stop(id: 1), stop(id: 2, sequence: 2, latitude: null, longitude: null)])),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('stop-2'), isFalse);
      expect(find.textContaining('1 stop has no location'), findsOneWidget);
    });

    testWidgets('half a coordinate is not a place', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1, longitude: null)])));
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('stop-1'), isFalse);
    });

    testWidgets('a school nobody has placed is not a pin', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1)], schoolLatitude: null, schoolLongitude: null)));
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('school'), isFalse);
      expect(renderer.markersById.containsKey('stop-1'), isTrue);
    });

    testWidgets('the pin says which state its stop is in', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [
              stop(id: 1, reached: true),
              stop(id: 2, sequence: 2, name: 'Central Park'),
              stop(id: 3, sequence: 3, name: 'Hill Road'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById['stop-1']!.infoWindow.snippet, 'Reached');
      expect(renderer.markersById['stop-2']!.infoWindow.snippet, 'Next stop');
      expect(renderer.markersById['stop-3']!.infoWindow.snippet, 'Still to come');
    });
  });

  testWidgets('the map is opened on what it has to show, not a guessed zoom', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(trip(stops: [stop(id: 1), stop(id: 2, sequence: 2)])));
    await tester.pumpAndSettle();

    // The framing itself is MapBounds.of, tested on its own. What this
    // pins is that the screen asks for it at all: without this the camera
    // keeps the centre and zoom the widget guessed, and a long route runs
    // off the edge.
    expect(renderer.lastView!.onMapCreated, isNotNull);
  });

  group('the line between them', () {
    testWidgets('a current road is drawn solid, the way Google sent it', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [stop(id: 1), stop(id: 2, sequence: 2)],
            path: const RoutePath(
              status: RoutePathStatus.ok,
              polyline: aRoad,
              distanceM: 13116,
              durationS: 2313,
              failureReason: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line = renderer.polylines.single;

      expect(line.polylineId.value, 'road');
      expect(line.points, hasLength(3));
      expect(line.patterns, isEmpty);
    });

    testWidgets('no road yet still draws the order of the stops', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1), stop(id: 2, sequence: 2)])));
      await tester.pumpAndSettle();

      final line = renderer.polylines.single;

      expect(line.polylineId.value, 'straight');
      // Two stops and the school, which the road would have ended at.
      expect(line.points, hasLength(3));
      expect(line.patterns, isNotEmpty);
      expect(find.textContaining('has not been worked out'), findsOneWidget);
    });

    testWidgets('a stale road is a stand-in, and says so', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [stop(id: 1), stop(id: 2, sequence: 2)],
            path: const RoutePath(
              status: RoutePathStatus.stale,
              polyline: aRoad,
              distanceM: 1,
              durationS: 1,
              failureReason: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The stored line is of where the stops used to be, so it is not the
      // one drawn - even though there is one.
      expect(renderer.polylines.single.polylineId.value, 'straight');
      expect(find.textContaining('changed since this road was worked out'), findsOneWidget);
    });

    testWidgets('a failed road falls back without blaming the reader', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [stop(id: 1), stop(id: 2, sequence: 2)],
            path: const RoutePath(
              status: RoutePathStatus.failed,
              polyline: null,
              distanceM: null,
              durationS: null,
              failureReason: 'Google could not be reached.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.polylines.single.polylineId.value, 'straight');
      expect(find.textContaining('could not be worked out'), findsOneWidget);
    });

    testWidgets('one place is not a line', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1)], schoolLatitude: null, schoolLongitude: null)));
      await tester.pumpAndSettle();

      expect(renderer.polylines, isEmpty);
    });

    testWidgets('a polyline it cannot read falls back rather than drawing half a road', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [stop(id: 1), stop(id: 2, sequence: 2)],
            path: const RoutePath(
              status: RoutePathStatus.ok,
              polyline: '!!!!',
              distanceM: 1,
              durationS: 1,
              failureReason: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.polylines.single.polylineId.value, 'straight');
    });
  });

  group('the bus on it', () {
    testWidgets('a shared position is a pin of its own, above the stops', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1)]), at: bus()));
      await tester.pumpAndSettle();

      final pin = renderer.markersById['bus'];

      expect(pin, isNotNull);
      expect(pin!.position.latitude, closeTo(18.52, 0.00001));
      // The bus often sits right on a stop, and it is the thing somebody
      // opened this for.
      expect(pin.zIndexInt, greaterThan(0));
    });

    testWidgets('no position shared is no bus pin, and the map still draws', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1), stop(id: 2, sequence: 2)])));
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('bus'), isFalse);
      expect(renderer.markersById.containsKey('stop-1'), isTrue);
    });

    testWidgets('half a position is not a place', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(stops: [stop(id: 1)]),
          at: bus(longitude: 'not a number'),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('bus'), isFalse);
    });

    testWidgets('a position off the earth is not a place', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(stops: [stop(id: 1)]),
          at: bus(latitude: '91.0'),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('bus'), isFalse);
    });

    testWidgets('a fresh bus is named, and nothing more', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1)]), at: bus(ageSeconds: 40)));
      await tester.pumpAndSettle();

      // The Bus location card above says when it was last seen, in full.
      // Saying it again under the map would be the same sentence twice.
      expect(find.text('Bus 04'), findsOneWidget);
      expect(find.textContaining('last seen'), findsNothing);
    });

    testWidgets('a greyed bus explains itself, because grey says nothing on its own', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1)]), at: bus(ageSeconds: 400, isStale: true)));
      await tester.pumpAndSettle();

      expect(find.text('Bus 04 - last seen 6 min ago'), findsOneWidget);
    });

    testWidgets('the pin itself says when it was last seen', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1)]), at: bus(ageSeconds: 140)));
      await tester.pumpAndSettle();

      expect(renderer.markersById['bus']!.infoWindow.snippet, 'Last seen 2 min ago');
    });

    testWidgets('the next stop pin carries the arrival when there is one', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(trip(stops: [stop(id: 1, reached: true), stop(id: 2, sequence: 2)]), at: bus(), eta: 300),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById['stop-2']!.infoWindow.snippet, 'Next stop - about 5 min away');
      // The reached stop says nothing about arriving; the bus has been.
      expect(renderer.markersById['stop-1']!.infoWindow.snippet, 'Reached');
    });

    testWidgets('no arrival worked out leaves the pin saying what it knows', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1, reached: true), stop(id: 2, sequence: 2)]), at: bus()));
      await tester.pumpAndSettle();

      expect(renderer.markersById['stop-2']!.infoWindow.snippet, 'Next stop');
    });

    testWidgets('the legend names the bus by its vehicle', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1)]), at: bus()));
      await tester.pumpAndSettle();

      expect(find.text('Bus 04'), findsOneWidget);
    });

    test('a fresh position is the bus; an old one is where it was', () {
      // Read from the server's own answer rather than worked out again
      // here: it knows when the position was recorded, and this only knows
      // what it was told.
      expect(busPinColour(bus(isStale: false)), MapPinColour.bus);
      expect(busPinColour(bus(isStale: true, ageSeconds: 400)), MapPinColour.busStale);
    });
  });

  group('keeping the bus up to date', () {
    Widget wrapCard(TransportTrip given, FakeTransportRepository fake) {
      renderer = FakeMapRenderer();

      return ProviderScope(
        overrides: [
          ...mapIsAvailable(renderer),
          ...mapPinsAreReady(),
          transportRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: TripMapCard(trip: given)),
          ),
        ),
      );
    }

    testWidgets('a running trip is asked where its bus is', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository()
        ..liveAnswers = [TripLiveLocation(tripId: 7, status: 'in_progress', position: bus(), nextStop: null)];

      await tester.pumpWidget(wrapCard(trip(stops: [stop(id: 1)]), fake));
      await tester.pumpAndSettle();

      expect(fake.liveCalls, greaterThan(0));
      expect(renderer.markersById.containsKey('bus'), isTrue);
    });

    testWidgets('a finished trip is never asked - its bus is not going anywhere', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository();

      await tester.pumpWidget(wrapCard(trip(status: TripStatus.completed, stops: [stop(id: 1, reached: true)]), fake));
      await tester.pumpAndSettle();

      expect(fake.liveCalls, 0);
      expect(renderer.markersById.containsKey('stop-1'), isTrue);
    });

    testWidgets('a failing poll leaves the map standing, without a bus on it', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository()..failLiveWith = Failure.network();

      await tester.pumpWidget(wrapCard(trip(stops: [stop(id: 1), stop(id: 2, sequence: 2)]), fake));
      await tester.pumpAndSettle();

      // The Bus location card above it is where a failure is reported; a
      // map that vanished on every dropped poll would be worse than one
      // with no bus on it.
      expect(renderer.markersById.containsKey('stop-1'), isTrue);
      expect(renderer.markersById.containsKey('bus'), isFalse);
    });
  });

  group('the legend', () {
    testWidgets('it names the colours on the map', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(trip(stops: [stop(id: 1, reached: true), stop(id: 2, sequence: 2)])));
      await tester.pumpAndSettle();

      expect(find.text('Reached'), findsOneWidget);
      expect(find.text('Next stop'), findsOneWidget);
      expect(find.text('Still to come'), findsOneWidget);
      expect(find.text('School'), findsOneWidget);
    });

    testWidgets('a finished trip is not told which stop is next', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            status: TripStatus.completed,
            stops: [stop(id: 1, reached: true), stop(id: 2, sequence: 2, reached: true)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Next stop'), findsNothing);
      expect(find.text('Reached'), findsOneWidget);
    });

    testWidgets('a current road needs no explaining', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [stop(id: 1), stop(id: 2, sequence: 2)],
            path: const RoutePath(
              status: RoutePathStatus.ok,
              polyline: aRoad,
              distanceM: 13116,
              durationS: 2313,
              failureReason: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('dashed line'), findsNothing);
      expect(find.textContaining('worked out'), findsNothing);
    });

    testWidgets('more than one unplaced stop is counted, not listed', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          trip(
            stops: [
              stop(id: 1),
              stop(id: 2, sequence: 2, latitude: null, longitude: null),
              stop(id: 3, sequence: 3, latitude: null, longitude: null),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('2 stops have no location'), findsOneWidget);
    });
  });
}
