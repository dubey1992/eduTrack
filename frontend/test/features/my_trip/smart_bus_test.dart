import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/my_trip/application/auto_reach.dart';
import 'package:edutrack_app/features/my_trip/data/battery_guard.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/map_navigator.dart';
import 'package:edutrack_app/features/my_trip/data/models/trip_mark.dart';
import 'package:edutrack_app/features/my_trip/data/models/my_route.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/features/my_trip/data/navigation_session.dart';
import 'package:edutrack_app/features/my_trip/data/phone_dialer.dart';
import 'package:edutrack_app/features/my_trip/data/trip_service.dart';
import 'package:edutrack_app/features/my_trip/data/trip_voice.dart';
import 'package:edutrack_app/features/my_trip/data/voice_search.dart';
import 'package:edutrack_app/features/my_trip/presentation/my_trip_screen.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

/// The smart bus (docs/mobile-apps-review.md, M7): a stop marked Reached by
/// itself, the spoken next-stop prompt, and "Running late".

// Main Gate's pin, and two places near it.
const _gateLat = '12.9700000';
const _gateLng = '77.5900000';

DevicePosition _at(double latitude, double longitude, {double accuracy = 8, bool mocked = false}) =>
    DevicePosition(latitude: latitude, longitude: longitude, accuracy: accuracy, isMocked: mocked);

/// About 20 m north of the gate, and about 110 m.
final _nearGate = _at(12.97018, 77.59);
final _pastGate = _at(12.97100, 77.59);

Map<String, dynamic> _pinnedTrip({
  int autoReachM = 50,
  String direction = 'pickup',
  List<Map<String, dynamic>>? riders,
}) => {
  ...tripJson(
    direction: direction,
    riders: riders,
    stops: [
      stopJson(101, 'Main Gate', 1, latitude: _gateLat, longitude: _gateLng),
      stopJson(102, 'Lake Road', 2),
    ],
  ),
  'auto_reach_m': autoReachM,
};

TransportTrip _trip({int autoReachM = 50, String direction = 'pickup', List<Map<String, dynamic>>? riders}) =>
    tripFromJson(_pinnedTrip(autoReachM: autoReachM, direction: direction, riders: riders));

void main() {
  group('a stop reached by itself', () {
    test('the next stop counts once the bus is within the distance', () {
      expect(stopReachedByItself(_trip(), _nearGate)?.id, 101);
      expect(stopReachedByItself(_trip(), _pastGate), isNull);
    });

    test('not when the school has it switched off', () {
      expect(stopReachedByItself(_trip(autoReachM: 0), _nearGate), isNull);
    });

    test('not from a fix too rough to tell, or a mocked one', () {
      expect(stopReachedByItself(_trip(), _at(12.97018, 77.59, accuracy: 120)), isNull);
      expect(stopReachedByItself(_trip(), _at(12.97018, 77.59, mocked: true)), isNull);
    });

    test('a short distance still trusts an ordinary fix', () {
      final trip = _trip(autoReachM: 25);

      expect(stopReachedByItself(trip, _at(12.97010, 77.59, accuracy: 28))?.id, 101);
    });

    test('only the next stop: one with no pin is left to the button', () {
      final reachedGate = tripFromJson({
        ..._pinnedTrip(),
        'stops': [
          stopJson(101, 'Main Gate', 1, latitude: _gateLat, longitude: _gateLng, reached: true),
          stopJson(102, 'Lake Road', 2),
        ],
      });

      expect(stopReachedByItself(reachedGate, _nearGate), isNull);
    });

    test('never on a trip that is over', () {
      final done = tripFromJson({..._pinnedTrip(), 'status': 'completed'});

      expect(stopReachedByItself(done, _nearGate), isNull);
    });
  });

  group('what is said aloud', () {
    test('the next stop and how many are waiting there on a pickup', () {
      expect(nextStopPrompt(_trip()), 'Next stop Main Gate, 2 children to pick up.');
    });

    test('one child is one child', () {
      final trip = tripFromJson({
        ..._pinnedTrip(),
        'stops': [stopJson(101, 'Main Gate', 1, reached: true), stopJson(102, 'Lake Road', 2)],
      });

      expect(nextStopPrompt(trip), 'Next stop Lake Road, 1 child to pick up.');
    });

    test('on a drop it is the children aboard who get off there', () {
      final trip = _trip(
        direction: 'drop',
        riders: [
          riderJson(1, 'Aarav Sharma', stopId: 101, status: 'boarded'),
          riderJson(2, 'Diya Patel', stopId: 101, status: 'absent'),
        ],
      );

      expect(nextStopPrompt(trip), 'Next stop Main Gate, 1 child to drop off.');
    });

    test('a stop with nobody waiting is just named, and the end is said', () {
      final none = _trip(riders: [riderJson(3, 'Kabir Rao', stopId: 102)]);
      expect(nextStopPrompt(none), 'Next stop Main Gate.');

      final allDone = tripFromJson({
        ..._pinnedTrip(),
        'stops': [stopJson(101, 'Main Gate', 1, reached: true), stopJson(102, 'Lake Road', 2, reached: true)],
      });
      expect(nextStopPrompt(allDone), 'That was the last stop.');
    });
  });

  group('the marks', () {
    test('an automatic Reached and a delay keep what the server needs', () {
      final auto = TripMark.now(tripId: 55, type: TripMarkType.stopReached, label: 'x', stopId: 101, auto: true);
      final late = TripMark.now(tripId: 55, type: TripMarkType.delay, label: 'y', minutes: 15);
      final tapped = TripMark.now(tripId: 55, type: TripMarkType.stopReached, label: 'z', stopId: 101);

      expect(auto.toSyncJson(), containsPair('auto', true));
      expect(late.toSyncJson(), allOf(containsPair('type', 'delay'), containsPair('minutes', 15)));
      expect(tapped.toSyncJson().containsKey('auto'), isFalse);
      // Saved on the phone and read back without signal.
      final again = TripMark.fromJson(late.toJson());
      expect((again.type, again.minutes), (TripMarkType.delay, 15));
      expect(TripMark.fromJson(auto.toJson()).auto, isTrue);
    });

    test("the office's timeline says what the bus did", () {
      final event = TripEvent.fromJson(const {
        'id': 9,
        'type': 'delay_reported',
        'stop_id': null,
        'stop_name': null,
        'student_id': null,
        'student_name': null,
        'recorded_by_name': 'Asha',
        'recorded_at': '2026-09-19T01:40:00Z',
        'recorded_at_label': '7:10 AM',
        'note': 'Running about 15 minutes late',
      });
      expect(event.description, 'Running about 15 minutes late - parents told');

      final auto = TripEvent.fromJson(const {
        'id': 10,
        'type': 'stop_reached',
        'stop_id': 101,
        'stop_name': 'Main Gate',
        'student_id': null,
        'student_name': null,
        'recorded_by_name': 'Asha',
        'recorded_at': '2026-09-19T01:41:00Z',
        'recorded_at_label': '7:11 AM',
        'note': 'Reached automatically',
      });
      expect(auto.description, 'Bus reached Main Gate (marked automatically)');
    });
  });

  group('on the trip screen', () {
    late FakeMyTripApi api;
    late InMemoryKeyValueStore store;
    late FakeLocationSource location;
    late FakeTripVoice voice;

    setUp(() {
      api = FakeMyTripApi(trip: _pinnedTrip());
      store = InMemoryKeyValueStore();
      location = FakeLocationSource(access: LocationAccess.denied);
      voice = FakeTripVoice();
    });

    Future<void> openRunningTrip(WidgetTester tester) async {
      tester.view.physicalSize = const Size(480, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      api.routes = myRoutesJson(pickup: api.serverTrip);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myTripApiProvider.overrideWithValue(api),
            keyValueStoreProvider.overrideWithValue(store),
            locationSourceProvider.overrideWithValue(location),
            tripServiceProvider.overrideWithValue(FakeTripService()),
            phoneDialerProvider.overrideWithValue(FakePhoneDialer()),
            mapNavigatorProvider.overrideWithValue(FakeMapNavigator()),
            batteryGuardProvider.overrideWithValue(FakeBatteryGuard()),
            navigationSessionProvider.overrideWithValue(FakeNavigationSession()),
            voiceSearchProvider.overrideWithValue(FakeVoiceSearch()),
            tripVoiceProvider.overrideWithValue(voice),
          ],
          child: MaterialApp(
            theme: AppTheme.crewLight(),
            home: const Scaffold(body: MyTripScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue-pickup')));
      await tester.pumpAndSettle();
    }

    testWidgets('opening a running trip says the next stop, once', (tester) async {
      await openRunningTrip(tester);

      expect(voice.said, ['Next stop Main Gate, 2 children to pick up.']);
    });

    testWidgets('the bus at the stop marks it Reached by itself, and says the next one', (tester) async {
      location.access = LocationAccess.granted;
      await openRunningTrip(tester);

      location.offer(_nearGate);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reach-stop-101')), findsNothing);
      final op = api.syncedOps.firstWhere((op) => op['type'] == 'stop_reached');
      expect(op, allOf(containsPair('stop_id', 101), containsPair('auto', true)));
      expect(voice.said.last, 'Next stop Lake Road, 1 child to pick up.');
    });

    testWidgets('a position short of the stop marks nothing', (tester) async {
      location.access = LocationAccess.granted;
      await openRunningTrip(tester);

      location.offer(_pastGate);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reach-stop-101')), findsOneWidget);
      expect(api.syncedOps.where((op) => op['type'] == 'stop_reached'), isEmpty);
    });

    testWidgets('the speaker button mutes the prompts, and the phone remembers', (tester) async {
      await openRunningTrip(tester);
      voice.said.clear();

      await tester.tap(find.byKey(const Key('trip-voice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reach-stop-101')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(voice.said, isEmpty);
      expect(await store.read('my_trip.speak_prompts'), 'false');
    });

    testWidgets('Running late offers 10, 15 and 30 minutes and tells the parents', (tester) async {
      await openRunningTrip(tester);

      await tester.tap(find.byKey(const Key('trip-late')));
      await tester.pumpAndSettle();
      expect(find.text('About 10 minutes late'), findsOneWidget);
      expect(find.text('About 30 minutes late'), findsOneWidget);

      await tester.tap(find.byKey(const Key('trip-late-15')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(api.syncedOps.last, allOf(containsPair('type', 'delay'), containsPair('minutes', 15)));
      expect(find.text('Parents told: about 15 minutes late.'), findsOneWidget);
    });

    testWidgets('closing the choices sends nothing', (tester) async {
      await openRunningTrip(tester);

      await tester.tap(find.byKey(const Key('trip-late')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(240, 40));
      await tester.pumpAndSettle();

      expect(api.syncedOps.where((op) => op['type'] == 'delay'), isEmpty);
    });
  });
}
