import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/transport/application/live_trip_notifier.dart';
import 'package:edutrack_app/features/transport/application/trip_history_notifier.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const _params = LiveTripParams(routeId: 1);

void main() {
  ProviderContainer makeContainer(FakeTransportRepository fake) {
    final container = ProviderContainer(
      overrides: [transportRepositoryProvider.overrideWithValue(fake)],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    container.listen(liveTripProvider(_params), (_, _) {});
    return container;
  }

  group('LiveTripNotifier', () {
    test('build() resolves to null when the route has no trip in progress', () async {
      final container = makeContainer(FakeTransportRepository(routes: [greenPark]));

      expect(await container.read(liveTripProvider(_params).future), isNull);
    });

    test('build() loads the in-progress trip with its detail', () async {
      final container = makeContainer(FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]));

      final trip = await container.read(liveTripProvider(_params).future);

      expect(trip!.id, 1);
      expect(trip.riders, hasLength(2));
      expect(trip.stops, hasLength(2));
    });

    test('start() creates the trip with the route\'s riders and stops', () async {
      final fake = FakeTransportRepository(routes: [greenPark], ridersForNewTrip: [arjunTripRider, meeraTripRider]);
      final container = makeContainer(fake);
      await container.read(liveTripProvider(_params).future);

      await container.read(liveTripProvider(_params).notifier).start(TripDirection.drop);

      final trip = container.read(liveTripProvider(_params)).value!;
      expect(trip.isInProgress, isTrue);
      expect(trip.direction, TripDirection.drop);
      expect(trip.ridersCount, 2);
      expect(trip.pendingCount, 2);
      expect(trip.stops.map((s) => s.name), ['Lake View', 'Central Park']);
      expect(trip.events.single.type, TripEventType.started);
      expect(fake.lastCall, {'op': 'startTrip', 'route_id': 1, 'direction': 'drop'});
    });

    test('reachStop(), updateRider() and end() move the trip through its lifecycle', () async {
      final fake = FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]);
      final container = makeContainer(fake);
      await container.read(liveTripProvider(_params).future);
      final notifier = container.read(liveTripProvider(_params).notifier);

      await notifier.reachStop(101);
      var trip = container.read(liveTripProvider(_params)).value!;
      expect(trip.currentStopName, 'Lake View');
      expect(trip.stops.first.reached, isTrue);
      expect(trip.stopsLeft, 1);

      await notifier.updateRider(7, TripRiderStatus.boarded);
      trip = container.read(liveTripProvider(_params)).value!;
      expect(trip.boardedCount, 1);
      expect(trip.riders.firstWhere((r) => r.studentId == 7).status, TripRiderStatus.boarded);
      expect(trip.events.last.type, TripEventType.boarded);

      await notifier.updateRider(7, TripRiderStatus.dropped);
      await notifier.end();
      trip = container.read(liveTripProvider(_params)).value!;
      expect(trip.status, TripStatus.completed);
      expect(trip.droppedCount, 1);
      expect(trip.absentCount, 1); // Meera never boarded
      expect(trip.pendingCount, 0);
      expect(trip.endedAt, isNotNull);
    });

    test('end() surfaces the riders-on-board failure and keeps the trip in progress', () async {
      final fake = FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]);
      final container = makeContainer(fake);
      await container.read(liveTripProvider(_params).future);
      final notifier = container.read(liveTripProvider(_params).notifier);
      await notifier.updateRider(7, TripRiderStatus.boarded);

      await expectLater(notifier.end(), throwsA(isA<Failure>().having((f) => f.code, 'code', 'TRIP_RIDERS_ON_BOARD')));
      expect(container.read(liveTripProvider(_params)).value!.isInProgress, isTrue);
    });

    test('cancel() marks the trip cancelled', () async {
      final container = makeContainer(FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]));
      await container.read(liveTripProvider(_params).future);

      await container.read(liveTripProvider(_params).notifier).cancel();

      expect(container.read(liveTripProvider(_params)).value!.status, TripStatus.cancelled);
    });
  });

  group('TripHistoryNotifier', () {
    test('lists trips newest first and filters by route', () async {
      final fake = FakeTransportRepository(
        routes: [greenPark],
        trips: [
          greenParkTrip,
          greenParkTrip.copyWith(status: TripStatus.completed),
        ],
      );
      final container = makeContainer(fake);

      final page = await container.read(tripHistoryNotifierProvider.future);
      expect(page.items, hasLength(2));

      await container.read(tripHistoryNotifierProvider.notifier).setFilters(routeId: 99);
      expect(container.read(tripHistoryNotifierProvider).value!.items, isEmpty);
      expect(fake.lastListCall!['route_id'], 99);
    });
  });
}
