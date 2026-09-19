import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/my_trip/application/location_sharing_notifier.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

/// Sharing runs on a 15-second timer, so these run as widget tests:
/// `tester.pump(duration)` moves the clock.
void main() {
  late FakeMyTripApi api;
  late InMemoryKeyValueStore store;
  late FakeLocationSource location;

  setUp(() {
    api = FakeMyTripApi();
    store = InMemoryKeyValueStore();
    location = FakeLocationSource();
  });

  /// A phone with the trip screen open: the provider is watched, as the
  /// switch on the screen watches it.
  ProviderContainer openTrip() {
    final container = ProviderContainer(
      overrides: [
        myTripApiProvider.overrideWithValue(api),
        keyValueStoreProvider.overrideWithValue(store),
        locationSourceProvider.overrideWithValue(location),
      ],
    );
    container.listen(locationSharingProvider(55), (_, _) {});
    return container;
  }

  LocationSharingState stateOf(ProviderContainer container) => container.read(locationSharingProvider(55));

  testWidgets('is on by default, and sends a position straight away and every 15 seconds', (tester) async {
    final container = openTrip();
    await tester.pump();

    expect(stateOf(container).enabled, isTrue);
    expect(api.locationBatches, hasLength(1));
    expect(api.locationBatches.single.single.accuracy, 8);
    expect(api.locationBatches.single.single.recordedAt, endsWith('Z'));

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    expect(api.locationBatches, hasLength(3));

    container.dispose();
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
    await tester.pump(const Duration(seconds: 15));
    expect(api.locationBatches, isEmpty);
    expect(store.values['my_trip.points'], contains('"trip_id":55'));

    api.offline = false;
    await tester.pump(const Duration(seconds: 15));
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
}
