import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/my_trip/application/location_sharing_notifier.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/trip_service.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

/// Sharing runs on a stream and a one-minute heartbeat timer, so these run
/// as widget tests: `tester.pump(duration)` moves the clock, and
/// `location.offer(...)` plays the part of the platform deciding the bus
/// has moved.
void main() {
  late FakeMyTripApi api;
  late InMemoryKeyValueStore store;
  late FakeLocationSource location;
  late FakeTripService service;

  setUp(() {
    api = FakeMyTripApi();
    store = InMemoryKeyValueStore();
    location = FakeLocationSource();
    service = FakeTripService();
  });

  /// A phone with the trip screen open: the provider is watched, as the
  /// switch on the screen watches it.
  ProviderContainer openTrip() {
    final container = ProviderContainer(
      overrides: [
        myTripApiProvider.overrideWithValue(api),
        keyValueStoreProvider.overrideWithValue(store),
        locationSourceProvider.overrideWithValue(location),
        tripServiceProvider.overrideWithValue(service),
      ],
    );
    container.listen(locationSharingProvider(55), (_, _) {});
    return container;
  }

  LocationSharingState stateOf(ProviderContainer container) => container.read(locationSharingProvider(55));

  /// The first fix the fake gives is 12.971, so these are measured from
  /// there: about 11 m away, and about 222 m away.
  const nearby = DevicePosition(latitude: 12.9711, longitude: 77.59, accuracy: 8);
  const farOff = DevicePosition(latitude: 12.9730, longitude: 77.59, accuracy: 8);
  const farther = DevicePosition(latitude: 12.9750, longitude: 77.59, accuracy: 8);

  testWidgets('is on by default, and sends a position straight away', (tester) async {
    final container = openTrip();
    await tester.pump();

    expect(stateOf(container).enabled, isTrue);
    expect(api.locationBatches, hasLength(1));
    expect(api.locationBatches.single.single.accuracy, 8);
    expect(api.locationBatches.single.single.recordedAt, endsWith('Z'));

    container.dispose();
  });

  group('what is worth sending (docs/driver-app.md, D4.2)', () {
    testWidgets('the platform is asked to do the filtering', (tester) async {
      final container = openTrip();
      await tester.pump();

      expect(location.askedDistanceFilter, LocationSharingNotifier.movedEnoughMetres);
      expect(location.askedInterval, LocationSharingNotifier.interval);

      container.dispose();
    });

    testWidgets('a bus that has moved is reported', (tester) async {
      final container = openTrip();
      await tester.pump();

      location.offer(farOff);
      await tester.pump();

      expect(api.locationBatches, hasLength(2));
      expect(api.locationBatches.last.single.latitude, farOff.latitude);

      container.dispose();
    });

    testWidgets('a bus that has not moved is not reported again', (tester) async {
      final container = openTrip();
      await tester.pump();

      location.offer(nearby);
      location.offer(nearby);
      await tester.pump();

      expect(api.locationBatches, hasLength(1), reason: 'eleven metres is a parked bus, not a journey');

      container.dispose();
    });

    testWidgets('a standing bus still says where it is once a minute', (tester) async {
      final container = openTrip();
      await tester.pump();
      expect(api.locationBatches, hasLength(1));

      await tester.pump(LocationSharingNotifier.heartbeat);
      await tester.pump();

      expect(api.locationBatches, hasLength(2));
      expect(location.positionsTaken, 2, reason: 'a real fix, not the last one stamped again');

      container.dispose();
    });

    testWidgets('a moving bus never reaches the heartbeat', (tester) async {
      final container = openTrip();
      await tester.pump();

      // Half a minute apart, so the heartbeat would have fired twice were
      // it not re-armed by each point.
      for (final position in [farOff, farther]) {
        await tester.pump(const Duration(seconds: 30));
        location.offer(position);
        await tester.pump();
      }

      expect(api.locationBatches, hasLength(3));
      expect(location.positionsTaken, 1, reason: 'only the opening fix was asked for');

      container.dispose();
    });

    testWidgets('the phone going quiet turns the switch off with the reason', (tester) async {
      final container = openTrip();
      await tester.pump();

      location.fail(LocationAccess.serviceOff);
      await tester.pump();

      expect(stateOf(container).enabled, isFalse);
      expect(stateOf(container).message, LocationSharingNotifier.serviceOffMessage);

      container.dispose();
    });
  });

  testWidgets('permission refused turns the switch off and says why', (tester) async {
    location.access = LocationAccess.denied;
    final container = openTrip();
    await tester.pump();

    expect(stateOf(container).enabled, isFalse);
    expect(stateOf(container).message, LocationSharingNotifier.deniedMessage);
    await tester.pump(const Duration(seconds: 30));
    expect(api.locationBatches, isEmpty);

    container.dispose();
  });

  testWidgets('permission blocked for good, or location off, each has its own message', (tester) async {
    location.access = LocationAccess.deniedForever;
    var container = openTrip();
    await tester.pump();
    expect(stateOf(container).message, LocationSharingNotifier.blockedMessage);
    container.dispose();

    location.access = LocationAccess.serviceOff;
    container = openTrip();
    await tester.pump();
    expect(stateOf(container).message, LocationSharingNotifier.serviceOffMessage);
    container.dispose();
  });

  testWidgets('stops when the server says the trip is no longer running', (tester) async {
    api.locationsError = apiError('/locations', 409, 'TRIP_NOT_IN_PROGRESS', 'This trip is no longer in progress.');
    final container = openTrip();
    await tester.pump();

    expect(stateOf(container).enabled, isFalse);
    expect(stateOf(container).message, LocationSharingNotifier.tripEndedMessage);

    final taken = location.positionsTaken;
    await tester.pump(const Duration(seconds: 45));
    expect(location.positionsTaken, taken, reason: 'no more positions once stopped');

    container.dispose();
  });

  testWidgets('with no signal, points wait on the phone and go together with the next batch', (tester) async {
    api.offline = true;
    final container = openTrip();
    await tester.pump();
    location.offer(farOff);
    await tester.pump();
    expect(api.locationBatches, isEmpty);
    expect(store.values['my_trip.points'], contains('"trip_id":55'));

    api.offline = false;
    location.offer(farther);
    await tester.pump();
    expect(api.locationBatches.single, hasLength(3));
    expect(store.values['my_trip.points'], '[]');

    container.dispose();
  });

  testWidgets('switching it off stops sharing, and the choice is remembered', (tester) async {
    final container = openTrip();
    await tester.pump();
    await container.read(locationSharingProvider(55).notifier).setEnabled(false);
    await tester.pump(const Duration(seconds: 30));

    expect(stateOf(container).enabled, isFalse);
    expect(stateOf(container).message, isNull);
    expect(api.locationBatches, hasLength(1));
    container.dispose();

    // The next trip starts with it off.
    final next = openTrip();
    await tester.pump(const Duration(seconds: 30));
    expect(stateOf(next).enabled, isFalse);
    expect(api.locationBatches, hasLength(1));
    next.dispose();
  });

  testWidgets('leaving the screen stops sharing', (tester) async {
    final container = openTrip();
    await tester.pump();
    container.dispose();

    final taken = location.positionsTaken;
    await tester.pump(const Duration(seconds: 45));
    expect(location.positionsTaken, taken);
  });

  group('keeping the phone reporting with the screen off', () {
    // Android stops a backgrounded app's timers, and a driver's phone sits
    // in a cradle for most of a run. Without the service the bus vanishes
    // from the office's map a minute in (docs/driver-app.md, D4).
    test('sharing starts the service, and says what it is for', () async {
      final container = openTrip();
      await container.read(locationSharingProvider(55).notifier).setEnabled(true);

      expect(service.running, isTrue);
      expect(service.title, 'Trip in progress');
    });

    test('turning sharing off stops it, so the notification does not outlive it', () async {
      final container = openTrip();
      final notifier = container.read(locationSharingProvider(55).notifier);
      await notifier.setEnabled(true);

      await notifier.setEnabled(false);

      expect(service.running, isFalse);
      expect(service.stops, greaterThan(0));
    });

    test('and a refused permission never leaves it running', () async {
      location.access = LocationAccess.denied;
      final container = openTrip();

      await container.read(locationSharingProvider(55).notifier).setEnabled(true);

      expect(service.running, isFalse);
    });
  });
}
