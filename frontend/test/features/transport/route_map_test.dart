import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/maps/presentation/app_map.dart';
import 'package:edutrack_app/features/transport/data/models/transport_route.dart';
import 'package:edutrack_app/features/transport/presentation/widgets/route_map.dart';
import 'package:edutrack_app/features/transport/data/models/transport_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_map.dart';

/// Google's own documented sample, which decodes to three points.
const aRoad = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

TransportStop stop({
  int id = 1,
  int sequence = 1,
  String name = 'Main Gate',
  String? latitude = '18.5000000',
  String? longitude = '73.8000000',
}) {
  return TransportStop(
    id: id,
    routeId: 1,
    name: name,
    sequenceNumber: sequence,
    pickupTime: null,
    dropTime: null,
    studentsCount: 0,
    latitude: latitude,
    longitude: longitude,
  );
}

TransportRoute route({
  List<TransportStop> stops = const [],
  String? schoolLatitude = '18.5289000',
  String? schoolLongitude = '73.8744000',
  RoutePath path = const RoutePath.notComputed(),
}) {
  return TransportRoute(
    id: 1,
    schoolId: 1,
    schoolName: 'Bright Future',
    name: 'Green Park',
    label: 'Green Park',
    status: TransportStatus.active,
    vehicleId: null,
    vehicleName: null,
    vehicleRegistrationNumber: null,
    capacity: null,
    driverId: null,
    driverName: null,
    driverMobile: null,
    stopsCount: stops.length,
    studentsCount: 0,
    stops: stops,
    schoolLatitude: schoolLatitude,
    schoolLongitude: schoolLongitude,
    path: path,
  );
}

late FakeMapRenderer renderer;

Widget wrap(TransportRoute given) {
  renderer = FakeMapRenderer();

  return ProviderScope(
    overrides: [...mapIsAvailable(renderer), ...mapPinsAreReady()],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: RouteMap(route: given)),
      ),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A route's stops and the road between them (docs/maps.md, M2).
///
/// The rule it is built around: **the line is drawn whatever state the road
/// is in.** A straight line through the right stops in the right order
/// tells somebody most of what they opened the map for, and is a great deal
/// better than an empty map while the road is being worked out.
void main() {
  group('the pins', () {
    testWidgets('a pin for every placed stop, and one for the school', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          route(
            stops: [
              stop(id: 1),
              stop(id: 2, sequence: 2, name: 'Lake View'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById.keys.toSet(), {'school', 'stop-1', 'stop-2'});
    });

    testWidgets('a stop with no location is not drawn anywhere', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(route(stops: [stop(id: 1), stop(id: 2, sequence: 2, latitude: null, longitude: null)])),
      );
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('stop-2'), isFalse);
    });

    testWidgets('half a coordinate is no location', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(route(stops: [stop(id: 1, longitude: null)])));
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('stop-1'), isFalse);
    });

    testWidgets('a school nobody has placed has no pin and is said so', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(route(stops: [stop()], schoolLatitude: null, schoolLongitude: null)));
      await tester.pumpAndSettle();

      expect(renderer.markersById.containsKey('school'), isFalse);
      expect(find.textContaining('The school has no location'), findsOneWidget);
    });

    testWidgets('the stop pin says its order and its name', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(route(stops: [stop(id: 1, sequence: 3, name: 'Lake View')])));
      await tester.pumpAndSettle();

      expect(renderer.markersById['stop-1']!.infoWindow.title, '3. Lake View');
    });

    testWidgets('the school is drawn differently from the stops', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(route(stops: [stop()])));
      await tester.pumpAndSettle();

      expect(renderer.markersById['school']!.icon.toJson(), isNot(renderer.markersById['stop-1']!.icon.toJson()));
    });
  });

  group('the line', () {
    testWidgets('a current road is drawn as the road', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.ok,
        polyline: aRoad,
        distanceM: 12400,
        durationS: 1500,
        failureReason: null,
      );

      await tester.pumpWidget(wrap(route(stops: [stop()], path: path)));
      await tester.pumpAndSettle();

      final line = renderer.polylines.single;
      expect(line.polylineId.value, 'road');
      expect(line.points, hasLength(3));
      expect(line.patterns, isEmpty);
    });

    testWidgets('no road yet is a dashed line through the stops', (tester) async {
      // Better than an empty map: the right stops in the right order is
      // most of what somebody opened this for.
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          route(
            stops: [
              stop(id: 1),
              stop(id: 2, sequence: 2, latitude: '18.6', longitude: '73.9'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line = renderer.polylines.single;
      expect(line.polylineId.value, 'straight');
      expect(line.patterns, isNotEmpty);
      // Two stops and the school.
      expect(line.points, hasLength(3));
    });

    testWidgets('a stale road is drawn as straight lines, not as the old road', (tester) async {
      // The stored line is of where the stops used to be, which looks
      // current and is not.
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.stale,
        polyline: aRoad,
        distanceM: 12400,
        durationS: 1500,
        failureReason: null,
      );

      await tester.pumpWidget(wrap(route(stops: [stop()], path: path)));
      await tester.pumpAndSettle();

      expect(renderer.polylines.single.polylineId.value, 'straight');
    });

    testWidgets('a road the server claimed but did not send is not drawn', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.ok,
        polyline: null,
        distanceM: 12400,
        durationS: 1500,
        failureReason: null,
      );

      await tester.pumpWidget(wrap(route(stops: [stop()], path: path)));
      await tester.pumpAndSettle();

      expect(renderer.polylines.single.polylineId.value, 'straight');
    });

    testWidgets('a road that will not decode falls back rather than drawing half of it', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.ok,
        polyline: '~~~~~~~~',
        distanceM: 12400,
        durationS: 1500,
        failureReason: null,
      );

      await tester.pumpWidget(
        wrap(
          route(
            stops: [
              stop(id: 1),
              stop(id: 2, sequence: 2, latitude: '18.6', longitude: '73.9'),
            ],
            path: path,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderer.polylines.single.polylineId.value, 'straight');
    });

    testWidgets('one place is no line at all', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(route(stops: const [], schoolLatitude: '18.5289000', schoolLongitude: '73.8744000')),
      );
      await tester.pumpAndSettle();

      expect(renderer.polylines, isEmpty);
    });

    testWidgets('the stand-in joins the same places as the road would', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          route(
            stops: [
              stop(id: 1),
              stop(id: 2, sequence: 2, latitude: '18.6', longitude: '73.9'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final points = renderer.polylines.single.points;
      expect(points.first.latitude, closeTo(18.5, 0.001));
      expect(points.last.latitude, closeTo(18.5289, 0.001), reason: 'ends at the school');
    });
  });

  group('what it says about the road', () {
    testWidgets('a current road is quoted in kilometres and minutes', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.ok,
        polyline: aRoad,
        distanceM: 12400,
        durationS: 1500,
        failureReason: null,
      );

      await tester.pumpWidget(wrap(route(stops: [stop()], path: path)));
      await tester.pumpAndSettle();

      expect(find.text('By road: 12.4 km, about 25 min.'), findsOneWidget);
    });

    testWidgets('a stale road says it is being worked out', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.stale,
        polyline: null,
        distanceM: null,
        durationS: null,
        failureReason: null,
      );

      await tester.pumpWidget(wrap(route(stops: [stop()], path: path)));
      await tester.pumpAndSettle();

      expect(find.textContaining('being worked out'), findsOneWidget);
    });

    testWidgets('a failure says what Google said', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.failed,
        polyline: null,
        distanceM: null,
        durationS: null,
        failureReason: 'Waypoint is not on a road.',
      );

      await tester.pumpWidget(wrap(route(stops: [stop()], path: path)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Waypoint is not on a road.'), findsOneWidget);
    });

    testWidgets('a failure with no reason still says something', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.failed,
        polyline: null,
        distanceM: null,
        durationS: null,
        failureReason: null,
      );

      await tester.pumpWidget(wrap(route(stops: [stop()], path: path)));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be worked out'), findsOneWidget);
    });

    testWidgets('it counts the stops that have no location', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          route(
            stops: [
              stop(id: 1),
              stop(id: 2, sequence: 2, latitude: null, longitude: null),
              stop(id: 3, sequence: 3, latitude: null, longitude: null),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('2 stops have no location yet'), findsOneWidget);
    });

    testWidgets('one such stop is counted in the singular', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(route(stops: [stop(id: 1), stop(id: 2, sequence: 2, latitude: null, longitude: null)])),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1 stop has no location yet'), findsOneWidget);
    });

    testWidgets('a route with nothing placed asks for two places', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(route(stops: const [], schoolLatitude: null, schoolLongitude: null)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Place at least two'), findsOneWidget);
    });
  });

  group('with no map key', () {
    testWidgets('it says so and still says what the road is', (tester) async {
      useDesktop(tester);
      const path = RoutePath(
        status: RoutePathStatus.ok,
        polyline: aRoad,
        distanceM: 12400,
        durationS: 1500,
        failureReason: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [...mapIsUnavailable(), ...mapPinsAreReady()],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: RouteMap(
                  route: route(stops: [stop()], path: path),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(MapUnavailable.message), findsOneWidget);
      expect(find.text('By road: 12.4 km, about 25 min.'), findsOneWidget);
    });
  });

  group('what the stored road says about itself', () {
    test('a road is current only when there is one to draw', () {
      // "ok" with no polyline should not happen, and must not be treated
      // as a road if it does.
      expect(
        const RoutePath(
          status: RoutePathStatus.ok,
          polyline: aRoad,
          distanceM: 1,
          durationS: 1,
          failureReason: null,
        ).isCurrent,
        isTrue,
      );
      expect(
        const RoutePath(
          status: RoutePathStatus.ok,
          polyline: null,
          distanceM: 1,
          durationS: 1,
          failureReason: null,
        ).isCurrent,
        isFalse,
      );
    });

    test('no other state is current, whatever line it carries', () {
      for (final status in [RoutePathStatus.none, RoutePathStatus.stale, RoutePathStatus.failed]) {
        expect(
          RoutePath(status: status, polyline: aRoad, distanceM: 1, durationS: 1, failureReason: null).isCurrent,
          isFalse,
          reason: status.name,
        );
      }
    });

    test('only a current road needs no explaining', () {
      expect(const RoutePath.notComputed().needsExplaining, isTrue);
      expect(
        const RoutePath(
          status: RoutePathStatus.ok,
          polyline: aRoad,
          distanceM: 1,
          durationS: 1,
          failureReason: null,
        ).needsExplaining,
        isFalse,
      );
    });

    test('a status this build has never heard of is no road', () {
      // The safe reading of a word from a newer server: draw straight
      // lines rather than trust a line described in unknown terms.
      expect(RoutePathStatus.fromApiValue('computing'), RoutePathStatus.none);
      expect(RoutePathStatus.fromApiValue(null), RoutePathStatus.none);
      expect(RoutePathStatus.fromApiValue(42), RoutePathStatus.none);
    });

    test('an envelope with no path in it is no road', () {
      expect(RoutePath.fromJson(null).status, RoutePathStatus.none);
      expect(RoutePath.fromJson('nonsense').status, RoutePathStatus.none);
      expect(RoutePath.fromJson(<String, dynamic>{}).status, RoutePathStatus.none);
    });

    test('an empty polyline is no polyline', () {
      expect(RoutePath.fromJson({'status': 'ok', 'polyline': ''}).isCurrent, isFalse);
    });
  });
}
