import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_trip/application/location_sharing_notifier.dart';
import 'package:edutrack_app/features/my_trip/data/battery_guard.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/features/my_trip/data/trip_health_log.dart';
import 'package:edutrack_app/features/my_trip/data/trip_service.dart';
import 'package:edutrack_app/features/my_trip/presentation/trip_check_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

/// The trip log and the Trip check screen (docs/mobile-apps-review.md, M0):
/// the real-phone GPS test reads them.

final _start = DateTime(2026, 11, 18, 7, 30);

TripHealthEvent _event(TripHealthKind kind, int minutes, {int? trip = 55, int? count, String? detail}) =>
    TripHealthEvent(
      at: _start.add(Duration(minutes: minutes)),
      kind: kind,
      tripId: trip,
      count: count,
      detail: detail,
    );

class _Exempt implements BatteryGuard {
  _Exempt(this.exempt);

  final bool exempt;

  @override
  Future<bool> isExempt() async => exempt;

  @override
  Future<bool> askForExemption() async => exempt;
}

void main() {
  group('the summary of the last trip', () {
    test('counts what was taken, sent and waiting, and finds the longest gap', () {
      final summary = TripHealthSummary.of([
        _event(TripHealthKind.sharingOn, 0),
        _event(TripHealthKind.point, 0, count: 8),
        _event(TripHealthKind.sent, 0, count: 1),
        _event(TripHealthKind.point, 1, count: 9),
        _event(TripHealthKind.appPaused, 2, trip: null),
        // Seven minutes with nothing: what a phone pausing the app looks like.
        _event(TripHealthKind.point, 8, count: 12),
        _event(TripHealthKind.waiting, 8, count: 2),
        _event(TripHealthKind.sharingOff, 9, detail: 'Switched off'),
      ])!;

      expect(summary.points, 3);
      expect(summary.longestGap, const Duration(minutes: 7));
      expect(summary.longestGapAt, _start.add(const Duration(minutes: 1)));
      expect(summary.hadWorryingGap, isTrue);
      expect((summary.sent, summary.stillWaiting, summary.backgrounded), (1, 2, 1));
      expect(summary.stops, ['Switched off']);
    });

    test('a trip that kept a position every minute has no worrying gap', () {
      final summary = TripHealthSummary.of([
        for (var minute = 0; minute < 10; minute++) _event(TripHealthKind.point, minute),
        _event(TripHealthKind.sent, 10, count: 10),
      ])!;

      expect(summary.hadWorryingGap, isFalse);
      expect(summary.stillWaiting, 0);
    });

    test('only the most recent trip is summed', () {
      final summary = TripHealthSummary.of([
        _event(TripHealthKind.point, 0, trip: 54),
        _event(TripHealthKind.sent, 0, trip: 54, count: 40),
        _event(TripHealthKind.point, 60),
        _event(TripHealthKind.sent, 60, count: 1),
      ])!;

      expect((summary.tripId, summary.points, summary.sent), (55, 1, 1));
    });

    test('no trip yet is no summary', () {
      expect(TripHealthSummary.of([_event(TripHealthKind.appPaused, 0, trip: null)]), isNull);
    });
  });

  group('the log on the phone', () {
    test('survives the app being closed, and keeps only the newest', () async {
      final store = InMemoryKeyValueStore();
      final log = TripHealthLog(store);
      for (var i = 0; i < TripHealthLog.keep + 5; i++) {
        await log.add(TripHealthKind.point, tripId: 1, count: i);
      }

      final reopened = await TripHealthLog(store).events();

      expect(reopened, hasLength(TripHealthLog.keep));
      expect(reopened.first.count, 5);
    });

    test('an unreadable log starts again instead of failing the trip', () async {
      final store = InMemoryKeyValueStore();
      await store.write('trip_health_log', 'not json');

      expect(await TripHealthLog(store).events(), isEmpty);
    });

    testWidgets('a shared trip writes its own entries', (tester) async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [
          myTripApiProvider.overrideWithValue(FakeMyTripApi()),
          keyValueStoreProvider.overrideWithValue(store),
          locationSourceProvider.overrideWithValue(FakeLocationSource()),
          tripServiceProvider.overrideWithValue(FakeTripService()),
        ],
      );
      container.listen(locationSharingProvider(55), (_, _) {});
      await tester.pump();

      final kinds = (await container.read(tripHealthLogProvider).events()).map((event) => event.kind).toList();

      expect(kinds, containsAllInOrder([TripHealthKind.sharingOn, TripHealthKind.point, TripHealthKind.sent]));
      container.dispose();
    });
  });

  group('the Trip check screen', () {
    late List<String> shared;

    Future<void> show(WidgetTester tester, List<TripHealthEvent> events, {bool exempt = true}) async {
      final store = InMemoryKeyValueStore();
      final log = TripHealthLog(store);
      for (final event in events) {
        await log.add(event.kind, tripId: event.tripId, count: event.count, detail: event.detail);
      }
      shared = [];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripHealthLogProvider.overrideWithValue(TripHealthLog(store)),
            batteryGuardProvider.overrideWithValue(_Exempt(exempt)),
            shareTextProvider.overrideWithValue((text) async => shared.add(text)),
          ],
          child: MaterialApp(theme: AppTheme.crewLight(), home: const TripCheckScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with no trip yet, says how to get one', (tester) async {
      await show(tester, []);

      expect(find.textContaining('No trip has shared its location on this phone yet'), findsOneWidget);
      expect(find.text('Battery saving will not stop this app'), findsOneWidget);
    });

    testWidgets('a trip that kept sharing says so', (tester) async {
      await show(tester, [_event(TripHealthKind.point, 0), _event(TripHealthKind.point, 1)]);

      expect(find.text('No long gaps: the phone kept sharing the whole way.'), findsOneWidget);
    });

    testWidgets('the report can be shared, with no positions or names in it', (tester) async {
      await show(tester, [_event(TripHealthKind.point, 0, count: 8)], exempt: false);

      await tester.tap(find.byKey(const Key('trip-check-share')));
      await tester.pumpAndSettle();

      expect(shared.single, contains('Battery saving exemption: no'));
      expect(shared.single, contains('Positions taken: 1'));
      expect(shared.single, isNot(contains('12.97')));
    });

    testWidgets('the log can be cleared', (tester) async {
      await show(tester, [_event(TripHealthKind.point, 0)]);

      await tester.tap(find.byKey(const Key('trip-check-clear')));
      await tester.pumpAndSettle();

      expect(find.textContaining('No trip has shared its location on this phone yet'), findsOneWidget);
    });
  });
}
