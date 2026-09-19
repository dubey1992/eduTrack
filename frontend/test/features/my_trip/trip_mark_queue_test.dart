import 'dart:convert';

import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/my_trip/application/trip_mark_queue.dart';
import 'package:edutrack_app/features/my_trip/data/models/trip_mark.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

TripMark _mark(TripMarkType type, {int? stopId, int? studentId, String? label}) =>
    TripMark.now(tripId: 55, type: type, label: label ?? type.apiValue, stopId: stopId, studentId: studentId);

/// The queue runs on timers (its back-off), so these run as widget tests:
/// `tester.pump(duration)` moves the clock.
void main() {
  late FakeMyTripApi api;
  late InMemoryKeyValueStore store;

  setUp(() {
    api = FakeMyTripApi();
    store = InMemoryKeyValueStore();
  });

  ProviderContainer phone() => ProviderContainer(
    overrides: [myTripApiProvider.overrideWithValue(api), keyValueStoreProvider.overrideWithValue(store)],
  );

  List<dynamic> stored(String key) => jsonDecode(store.values[key] ?? '[]') as List<dynamic>;

  testWidgets('with no signal, marks stay on the phone and the queue says it is offline', (tester) async {
    api.offline = true;
    final container = phone();
    final queue = container.read(tripMarkQueueProvider.notifier);

    await queue.enqueue(_mark(TripMarkType.stopReached, stopId: 101));
    await queue.enqueue(_mark(TripMarkType.boarded, studentId: 1));
    await tester.pump();

    final state = container.read(tripMarkQueueProvider);
    expect(state.pendingCount, 2);
    expect(state.offline, isTrue);
    expect(state.sending, isFalse);
    expect(stored('my_trip.marks'), hasLength(2));
    expect(api.syncBatches, isEmpty);

    container.dispose();
  });

  testWidgets('sends oldest first, and takes applied and duplicate marks off the queue', (tester) async {
    final container = phone();
    final queue = container.read(tripMarkQueueProvider.notifier);
    final duplicate = _mark(TripMarkType.boarded, studentId: 2);
    api.alreadyRecorded.add(duplicate.clientId);

    await queue.enqueue(_mark(TripMarkType.stopReached, stopId: 101));
    await queue.enqueue(_mark(TripMarkType.boarded, studentId: 1));
    await queue.enqueue(duplicate);
    await tester.pump();

    expect(api.syncedOps.map((op) => op['type']), ['stop_reached', 'boarded', 'boarded']);
    final state = container.read(tripMarkQueueProvider);
    expect(state.pendingCount, 0);
    expect(state.notSent, isEmpty);
    expect(state.offline, isFalse);
    expect(stored('my_trip.marks'), isEmpty);

    container.dispose();
  });

  testWidgets('a rejected mark leaves the queue for the Not sent list, with its reason', (tester) async {
    const reason = 'The trip had already ended, so this mark was not recorded.';
    api.rejectTypes = {'absent': reason};
    final container = phone();
    final queue = container.read(tripMarkQueueProvider.notifier);

    await queue.enqueue(_mark(TripMarkType.absent, studentId: 2, label: 'Diya Patel absent'));
    await tester.pump();

    final state = container.read(tripMarkQueueProvider);
    expect(state.pendingCount, 0);
    expect(state.notSentFor(55).single.label, 'Diya Patel absent');
    expect(state.notSentFor(55).single.reason, reason);
    expect(stored('my_trip.not_sent'), hasLength(1));

    // Read and dismissed: gone, on the phone as well.
    await queue.dismissNotSent(state.notSent.single.clientId);
    expect(container.read(tripMarkQueueProvider).notSent, isEmpty);
    expect(stored('my_trip.not_sent'), isEmpty);

    container.dispose();
  });

  testWidgets('a batch the server refuses outright is not retried forever', (tester) async {
    api.syncError = apiError('/sync', 403, 'FORBIDDEN', 'This action is unauthorized.');
    final container = phone();

    await container.read(tripMarkQueueProvider.notifier).enqueue(_mark(TripMarkType.boarded, studentId: 1));
    await tester.pump();

    final state = container.read(tripMarkQueueProvider);
    expect(state.pendingCount, 0);
    expect(state.notSent.single.reason, 'This action is unauthorized.');

    container.dispose();
  });

  testWidgets('survives the app being closed: the next start sends what was waiting', (tester) async {
    api.offline = true;
    final before = phone();
    await before.read(tripMarkQueueProvider.notifier).enqueue(_mark(TripMarkType.stopReached, stopId: 101));
    await before.read(tripMarkQueueProvider.notifier).enqueue(_mark(TripMarkType.boarded, studentId: 1));
    await tester.pump();
    before.dispose();

    // Signal is back when the app is opened again.
    api.offline = false;
    final after = phone();
    after.read(tripMarkQueueProvider);
    await tester.pump();
    await tester.pump();

    expect(api.syncedOps.map((op) => op['type']), ['stop_reached', 'boarded']);
    expect(after.read(tripMarkQueueProvider).pendingCount, 0);

    after.dispose();
  });

  testWidgets('with no signal it tries again after 5, 15, 30 and then every 60 seconds', (tester) async {
    api.offline = true;
    final container = phone();
    await container.read(tripMarkQueueProvider.notifier).enqueue(_mark(TripMarkType.boarded, studentId: 1));
    await tester.pump();
    expect(api.syncAttempts, 1);

    Future<void> expectAttemptAfter(Duration wait, int attempts) async {
      await tester.pump(wait - const Duration(seconds: 1));
      expect(api.syncAttempts, attempts - 1, reason: 'not yet, before $wait');
      await tester.pump(const Duration(seconds: 1));
      expect(api.syncAttempts, attempts, reason: 'after $wait');
    }

    await expectAttemptAfter(const Duration(seconds: 5), 2);
    await expectAttemptAfter(const Duration(seconds: 15), 3);
    await expectAttemptAfter(const Duration(seconds: 30), 4);
    await expectAttemptAfter(const Duration(seconds: 60), 5);
    await expectAttemptAfter(const Duration(seconds: 60), 6);

    // Signal comes back: the next try sends it and the banner clears.
    api.offline = false;
    await tester.pump(const Duration(seconds: 60));
    expect(api.syncedOps, hasLength(1));
    expect(container.read(tripMarkQueueProvider).pendingCount, 0);
    expect(container.read(tripMarkQueueProvider).offline, isFalse);

    container.dispose();
  });

  testWidgets('trying now skips the rest of the wait', (tester) async {
    api.offline = true;
    final container = phone();
    final queue = container.read(tripMarkQueueProvider.notifier);
    await queue.enqueue(_mark(TripMarkType.boarded, studentId: 1));
    await tester.pump();

    api.offline = false;
    await queue.retryNow();
    await tester.pump();

    expect(api.syncedOps, hasLength(1));
    expect(container.read(tripMarkQueueProvider).pendingCount, 0);

    container.dispose();
  });

  testWidgets('discarding on sign-out forgets everything on the phone', (tester) async {
    api.offline = true;
    final container = phone();
    final queue = container.read(tripMarkQueueProvider.notifier);
    await queue.enqueue(_mark(TripMarkType.boarded, studentId: 1));
    await tester.pump();

    await queue.discardAll();

    expect(container.read(tripMarkQueueProvider).pendingCount, 0);
    expect(store.values.keys.where((key) => key.startsWith('my_trip.')), isEmpty);

    container.dispose();
  });
}
