import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:edutrack_app/features/transport/data/models/trip_live_location.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/widgets/trip_detail_view.dart';
import 'package:edutrack_app/features/transport/presentation/widgets/trip_live_location_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const _admin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

const _lakeViewNext = NextStop(
  id: 101,
  name: 'Lake View',
  sequenceNumber: 1,
  latitude: '18.530000',
  longitude: '73.860000',
  straightLineDistanceM: 1234,
);

TripLiveLocation _live({BusPosition? position, NextStop? nextStop = _lakeViewNext, String status = 'in_progress'}) {
  return TripLiveLocation(tripId: 1, status: status, position: position, nextStop: nextStop);
}

BusPosition _position({int ageSeconds = 120, bool isStale = false}) {
  return BusPosition(
    latitude: '18.520400',
    longitude: '73.856700',
    accuracyM: 12,
    speedMps: 8.5,
    heading: 90,
    recordedAt: '2026-09-10T07:40:00Z',
    ageSeconds: ageSeconds,
    isStale: isStale,
  );
}

/// The trip panel inside a switch, so a test can take it off the screen
/// the way leaving the page would.
class _Host extends StatefulWidget {
  const _Host({required this.trip});

  final TransportTrip trip;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _showing = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(onPressed: () => setState(() => _showing = false), child: const Text('Leave')),
        Expanded(
          child: SingleChildScrollView(child: _showing ? TripDetailView(trip: widget.trip) : const SizedBox()),
        ),
      ],
    );
  }
}

Widget wrap(FakeTransportRepository fake, TransportTrip trip) {
  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: _Host(trip: trip)),
    ),
  );
}

void _useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the live card on a running trip', () {
    testWidgets('shows when the bus was last seen, where, and how far the next stop is', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])..liveAnswers = [_live(position: _position())];
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();

      expect(find.text('Bus location'), findsOneWidget);
      expect(find.text('Last seen 2 min ago'), findsOneWidget);
      expect(find.text('18.520400, 73.856700'), findsOneWidget);
      expect(find.text('Open in maps'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Next stop: Lake View - about 1.2 km away (straight line)'), findsOneWidget);
    });

    testWidgets('a position the phone stopped updating is marked stale', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])
        ..liveAnswers = [_live(position: _position(ageSeconds: 725, isStale: true))];
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();

      expect(find.text('Last seen 12 min ago (stale)'), findsOneWidget);
    });

    testWidgets('before the phone shares anything it says so, and the next stop has no distance', (tester) async {
      _useDesktop(tester);
      const noDistance = NextStop(
        id: 101,
        name: 'Lake View',
        sequenceNumber: 1,
        latitude: null,
        longitude: null,
        straightLineDistanceM: null,
      );
      final fake = FakeTransportRepository(trips: [greenParkTrip])..liveAnswers = [_live(nextStop: noDistance)];
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();

      expect(find.text('No location shared yet.'), findsOneWidget);
      expect(find.text('Next stop: Lake View'), findsOneWidget);
      expect(find.text('Open in maps'), findsNothing);
    });

    testWidgets('every stop reached', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])
        ..liveAnswers = [_live(position: _position(), nextStop: null)];
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();

      expect(find.text('Every stop has been reached.'), findsOneWidget);
    });

    testWidgets('asks again every 15 seconds and shows the newer answer', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])
        ..liveAnswers = [_live(position: _position(ageSeconds: 30)), _live(position: _position(ageSeconds: 200))];
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();
      expect(fake.liveCalls, 1);
      expect(find.text('Last seen less than a minute ago'), findsOneWidget);

      await tester.pump(const Duration(seconds: 14));
      expect(fake.liveCalls, 1);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fake.liveCalls, 2);
      expect(find.text('Last seen 3 min ago'), findsOneWidget);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(fake.liveCalls, 3);
    });

    testWidgets('stops asking once the trip is no longer in progress', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])
        ..liveAnswers = [_live(position: _position()), _live(position: _position(), status: 'completed')];
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(fake.liveCalls, 2);

      await tester.pump(const Duration(minutes: 2));
      expect(fake.liveCalls, 2);
    });

    testWidgets('stops asking when the panel leaves the screen', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])..liveAnswers = [_live(position: _position())];
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();
      expect(fake.liveCalls, 1);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));

      expect(find.text('Bus location'), findsNothing);
      expect(fake.liveCalls, 1);
    });

    testWidgets('a failure shows the message with Retry, and keeps trying on its own', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])
        ..liveAnswers = [_live(position: _position())]
        ..failLiveWith = Failure.network();
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // The connection comes back: the next scheduled poll recovers by itself.
      fake.failLiveWith = null;
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(find.text('Last seen 2 min ago'), findsOneWidget);
    });

    testWidgets('Retry asks again straight away', (tester) async {
      _useDesktop(tester);
      final fake = FakeTransportRepository(trips: [greenParkTrip])
        ..liveAnswers = [_live(position: _position())]
        ..failLiveWith = Failure.network();
      await tester.pumpWidget(wrap(fake, greenParkTrip));
      await tester.pumpAndSettle();

      fake.failLiveWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(fake.liveCalls, 2);
      expect(find.text('Last seen 2 min ago'), findsOneWidget);
    });
  });

  testWidgets('a finished trip has no live card and asks nothing', (tester) async {
    _useDesktop(tester);
    final finished = greenParkTrip.copyWith(status: TripStatus.completed);
    final fake = FakeTransportRepository(trips: [finished]);
    await tester.pumpWidget(wrap(fake, finished));
    await tester.pumpAndSettle();

    expect(find.text('Bus location'), findsNothing);
    expect(fake.liveCalls, 0);
  });

  testWidgets('a call to a guardian appears on the timeline with a phone icon', (tester) async {
    _useDesktop(tester);
    final trip = greenParkTrip.copyWith(
      status: TripStatus.completed,
      events: [
        ...greenParkTrip.events,
        const TripEvent(
          id: 2,
          type: TripEventType.guardianCalled,
          stopId: null,
          stopName: null,
          studentId: 7,
          studentName: 'Arjun Kumar',
          recordedByName: 'Meera Sharma',
          recordedAt: '2026-09-10T07:40:00.000000Z',
          recordedAtLabel: '1:10 PM',
          note: 'Called Raj Kumar',
        ),
      ],
    );
    await tester.pumpWidget(wrap(FakeTransportRepository(trips: [trip]), trip));
    await tester.pumpAndSettle();

    expect(find.text("Meera Sharma called Arjun Kumar's guardian"), findsOneWidget);
    expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
  });

  test('a guardian_called event parses from the API', () {
    final event = TripEvent.fromJson({
      'id': 9,
      'type': 'guardian_called',
      'stop_id': null,
      'stop_name': null,
      'student_id': 7,
      'student_name': 'Arjun Kumar',
      'recorded_by_name': 'Meera Sharma',
      'recorded_at': '2026-09-10T07:40:00Z',
      'recorded_at_label': '1:10 PM',
      'note': 'Called Raj Kumar',
    });

    expect(event.type, TripEventType.guardianCalled);
    expect(event.description, "Meera Sharma called Arjun Kumar's guardian");
  });

  test('the live answer parses, with and without a position', () {
    final live = TripLiveLocation.fromJson({
      'trip_id': 1,
      'status': 'in_progress',
      'position': {
        'latitude': '18.520400',
        'longitude': '73.856700',
        'accuracy_m': 12,
        'speed_mps': 8.5,
        'heading': null,
        'recorded_at': '2026-09-10T07:40:00Z',
        'age_seconds': 125,
        'is_stale': false,
      },
      'next_stop': {
        'id': 101,
        'name': 'Lake View',
        'sequence_number': 1,
        'latitude': null,
        'longitude': null,
        'straight_line_distance_m': null,
      },
    });
    expect(live.isInProgress, isTrue);
    expect(live.position!.ageSeconds, 125);
    expect(live.position!.accuracyM, 12.0);
    expect(live.nextStop!.straightLineDistanceM, isNull);

    final empty = TripLiveLocation.fromJson({'trip_id': 1, 'status': 'completed', 'position': null, 'next_stop': null});
    expect(empty.isInProgress, isFalse);
    expect(empty.position, isNull);
    expect(empty.nextStop, isNull);
  });

  test('the labels read naturally', () {
    expect(lastSeenLabel(0), 'Last seen less than a minute ago');
    expect(lastSeenLabel(59), 'Last seen less than a minute ago');
    expect(lastSeenLabel(60), 'Last seen 1 min ago');
    expect(lastSeenLabel(3600), 'Last seen 1 h ago');
    expect(lastSeenLabel(3900), 'Last seen 1 h 5 min ago');

    expect(distanceLabel(348), 'about 350 m');
    expect(distanceLabel(999), 'about 1.0 km');
    expect(distanceLabel(1234), 'about 1.2 km');

    expect(
      mapsLink('18.520400', '73.856700').toString(),
      'https://www.google.com/maps/search/?api=1&query=18.520400%2C73.856700',
    );
  });
}
