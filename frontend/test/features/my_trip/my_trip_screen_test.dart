import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/status_badge.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/features/my_trip/data/phone_dialer.dart';
import 'package:edutrack_app/features/my_trip/presentation/my_trip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

void main() {
  late FakeMyTripApi api;
  late InMemoryKeyValueStore store;
  late FakeLocationSource location;
  late FakePhoneDialer dialer;

  setUp(() {
    api = FakeMyTripApi();
    store = InMemoryKeyValueStore();
    // Sharing has its own tests; kept out of the way here unless a test asks.
    location = FakeLocationSource(access: LocationAccess.denied);
    dialer = FakePhoneDialer();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // A tall phone, so the whole trip is laid out without scrolling.
    tester.view.physicalSize = const Size(480, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myTripApiProvider.overrideWithValue(api),
          keyValueStoreProvider.overrideWithValue(store),
          locationSourceProvider.overrideWithValue(location),
          phoneDialerProvider.overrideWithValue(dialer),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: MyTripScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens today's running pickup trip from the routes list.
  Future<void> openRunningTrip(WidgetTester tester) async {
    api.routes = myRoutesJson(pickup: api.serverTrip);
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('continue-pickup')));
    await tester.pumpAndSettle();
  }

  /// Taps, then waits out the double-tap guard.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  String statusOf(WidgetTester tester, int studentId) => tester
      .widget<StatusBadge>(find.descendant(of: find.byKey(Key('rider-$studentId')), matching: find.byType(StatusBadge)))
      .label;

  bool markEnabled(WidgetTester tester, String status, int studentId) => tester
      .widget<ButtonStyleButton>(
        find.descendant(of: find.byKey(Key('mark-$status-$studentId')), matching: find.bySubtype<ButtonStyleButton>()),
      )
      .enabled;

  bool endEnabled(WidgetTester tester) => tester.widget<ButtonStyleButton>(find.byKey(const Key('end-trip'))).enabled;

  group('the routes page', () {
    testWidgets("shows today's date and a Start button for trips not yet run", (tester) async {
      await pumpScreen(tester);

      expect(find.text('Saturday, September 19, 2026'), findsOneWidget);
      expect(find.text('North Loop'), findsOneWidget);
      expect(find.byKey(const Key('start-pickup')), findsOneWidget);
      expect(find.byKey(const Key('start-drop')), findsOneWidget);
    });

    testWidgets('starting a trip opens it with its stops and children', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('start-pickup')));
      await tester.pumpAndSettle();

      expect(api.startCalls, 1);
      expect(find.text('North Loop - Pickup'), findsOneWidget);
      expect(find.text('1. Main Gate · 07:11'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Kabir Rao'), findsOneWidget);
    });

    testWidgets('starting with no signal says a connection is needed', (tester) async {
      await pumpScreen(tester);
      api.offline = true;

      await tester.tap(find.byKey(const Key('start-pickup')));
      await tester.pumpAndSettle();

      expect(find.text('Starting a trip needs a connection. Try again when you have signal.'), findsOneWidget);
      expect(find.text('North Loop - Pickup'), findsNothing);
    });

    testWidgets("the server's refusal is shown as it said it", (tester) async {
      api.startError = apiError('/transport/trips', 409, 'TRIP_ON_NON_WORKING_DAY', 'Trips do not run on weekends.');
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('start-pickup')));
      await tester.pumpAndSettle();

      expect(find.text('Trips do not run on weekends.'), findsOneWidget);
    });

    testWidgets('a running trip offers Continue, and a finished one its summary', (tester) async {
      api.routes = myRoutesJson(
        pickup: tripJson(),
        drop: tripJson(id: 56, status: 'completed', direction: 'drop'),
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('continue-pickup')), findsOneWidget);
      expect(find.byKey(const Key('view-drop')), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('with no route assigned, says so', (tester) async {
      api.routes = {'date': '2026-09-19', 'routes': <dynamic>[]};
      await pumpScreen(tester);

      expect(find.textContaining('No route is assigned to you yet'), findsOneWidget);
    });

    testWidgets('with no signal and nothing saved, shows the error with a retry', (tester) async {
      api.offline = true;
      await pumpScreen(tester);

      expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);

      api.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('North Loop'), findsOneWidget);
    });
  });

  group('running a trip', () {
    testWidgets('only the next stop offers Reached, and reaching it moves on', (tester) async {
      await openRunningTrip(tester);

      expect(find.byKey(const Key('reach-stop-101')), findsOneWidget);
      expect(find.byKey(const Key('reach-stop-102')), findsNothing);

      await tapAndSettle(tester, find.byKey(const Key('reach-stop-101')));

      expect(find.byKey(const Key('reach-stop-101')), findsNothing);
      expect(find.byKey(const Key('reach-stop-102')), findsOneWidget);
      expect(api.syncedOps.single, containsPair('type', 'stop_reached'));
      expect(api.syncedOps.single, containsPair('stop_id', 101));
    });

    testWidgets('a waiting child can board or be absent, not be dropped', (tester) async {
      await openRunningTrip(tester);

      expect(statusOf(tester, 1), 'Pending');
      expect(markEnabled(tester, 'boarded', 1), isTrue);
      expect(markEnabled(tester, 'absent', 1), isTrue);
      expect(markEnabled(tester, 'dropped', 1), isFalse);
    });

    testWidgets('boarding shows at once, then only Dropped is offered', (tester) async {
      await openRunningTrip(tester);

      await tapAndSettle(tester, find.byKey(const Key('mark-boarded-1')));

      expect(statusOf(tester, 1), 'Boarded');
      expect(markEnabled(tester, 'boarded', 1), isFalse);
      expect(markEnabled(tester, 'absent', 1), isFalse);
      expect(markEnabled(tester, 'dropped', 1), isTrue);
      expect(api.syncedOps.single, containsPair('student_id', 1));

      await tapAndSettle(tester, find.byKey(const Key('mark-dropped-1')));
      expect(statusOf(tester, 1), 'Dropped');
      for (final status in ['boarded', 'dropped', 'absent']) {
        expect(markEnabled(tester, status, 1), isFalse, reason: status);
      }
    });

    testWidgets('an absent child is final', (tester) async {
      await openRunningTrip(tester);

      await tapAndSettle(tester, find.byKey(const Key('mark-absent-2')));

      expect(statusOf(tester, 2), 'Absent');
      for (final status in ['boarded', 'dropped', 'absent']) {
        expect(markEnabled(tester, status, 2), isFalse, reason: status);
      }
    });

    testWidgets('a quick double tap is one mark', (tester) async {
      await openRunningTrip(tester);

      await tester.tap(find.byKey(const Key('mark-boarded-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mark-dropped-1')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(statusOf(tester, 1), 'Boarded');
      expect(api.syncedOps, hasLength(1));
    });

    testWidgets('End trip is off while anybody is aboard, and asks before ending', (tester) async {
      await openRunningTrip(tester);
      expect(endEnabled(tester), isTrue);

      await tapAndSettle(tester, find.byKey(const Key('mark-boarded-1')));
      expect(endEnabled(tester), isFalse);
      expect(find.text('1 child is still on board. Drop them off before ending the trip.'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('mark-dropped-1')));
      expect(endEnabled(tester), isTrue);

      await tapAndSettle(tester, find.byKey(const Key('end-trip')));
      expect(find.text('End this trip?'), findsOneWidget);
      expect(find.text('2 children have not been marked and will be recorded as absent.'), findsOneWidget);

      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'End trip').last);

      expect(find.text('Trip ended.'), findsOneWidget);
      expect(find.byKey(const Key('end-trip')), findsNothing);
      expect(api.syncedOps.last, containsPair('type', 'end'));
      expect(statusOf(tester, 2), 'Absent');
    });

    testWidgets('keeping going after the question ends nothing', (tester) async {
      await openRunningTrip(tester);

      await tapAndSettle(tester, find.byKey(const Key('end-trip')));
      await tapAndSettle(tester, find.text('Keep going'));

      expect(find.byKey(const Key('end-trip')), findsOneWidget);
      expect(api.syncedOps, isEmpty);
    });
  });

  group('Call parent', () {
    testWidgets("opens the dialler with the guardian's number and records the call", (tester) async {
      await openRunningTrip(tester);

      await tapAndSettle(tester, find.byKey(const Key('call-parent-1')));

      expect(dialer.dialled, ['+91 98765 43210']);
      expect(api.syncedOps.single, containsPair('type', 'guardian_called'));
      expect(api.syncedOps.single, containsPair('student_id', 1));
    });

    testWidgets('never shows the number itself', (tester) async {
      await openRunningTrip(tester);

      expect(find.textContaining('98765'), findsNothing);
    });

    testWidgets('is off for a child with no number on record', (tester) async {
      await openRunningTrip(tester);

      expect(tester.widget<IconButton>(find.byKey(const Key('call-parent-3'))).onPressed, isNull);
      expect(find.byTooltip('No number on record'), findsOneWidget);
    });

    testWidgets('says so when the dialler cannot be opened, and records nothing', (tester) async {
      dialer.opens = false;
      await openRunningTrip(tester);

      await tapAndSettle(tester, find.byKey(const Key('call-parent-1')));

      expect(find.text("Could not open the phone's dialler."), findsOneWidget);
      expect(api.syncedOps, isEmpty);
    });

    test('dials the digits of the number', () {
      expect(telUri('+91 98765 43210').toString(), 'tel:+919876543210');
      expect(telUri('080-2345-6789').toString(), 'tel:08023456789');
    });
  });

  group('with no signal', () {
    testWidgets('marks still show at once, and the banner counts what is waiting', (tester) async {
      await openRunningTrip(tester);
      api.offline = true;

      await tapAndSettle(tester, find.byKey(const Key('reach-stop-101')));
      await tapAndSettle(tester, find.byKey(const Key('mark-boarded-1')));

      expect(statusOf(tester, 1), 'Boarded');
      expect(find.text('Offline - 2 marks waiting to send'), findsOneWidget);

      // Signal is back.
      api.offline = false;
      await tapAndSettle(tester, find.text('Send now'));

      expect(find.byKey(const Key('my-trip-sync-banner')), findsNothing);
      expect(api.syncedOps.map((op) => op['type']), ['stop_reached', 'boarded']);
      expect(statusOf(tester, 1), 'Boarded');
    });

    testWidgets('a mark the server turned down is listed as not sent until dismissed', (tester) async {
      api.rejectTypes = {'absent': 'The trip had already ended, so this mark was not recorded.'};
      await openRunningTrip(tester);

      await tapAndSettle(tester, find.byKey(const Key('mark-absent-2')));

      expect(find.text('Not sent'), findsOneWidget);
      expect(find.text('Diya Patel absent'), findsOneWidget);
      expect(find.text('The trip had already ended, so this mark was not recorded.'), findsOneWidget);
      // Not applied on the server, so no longer shown as absent either.
      expect(statusOf(tester, 2), 'Pending');

      await tapAndSettle(tester, find.byTooltip('Dismiss'));
      expect(find.byKey(const Key('not-sent-card')), findsNothing);
    });

    testWidgets('an app opened with no signal shows the routes and trip saved on the phone', (tester) async {
      // Used once with signal, which saved both...
      await openRunningTrip(tester);
      await tester.pumpWidget(const SizedBox());

      // ...then opened again on the bus.
      api.offline = true;
      await pumpScreen(tester);

      expect(find.text('No signal - showing your routes as last saved on this phone.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('continue-pickup')));
      await tester.pumpAndSettle();

      expect(find.text('No signal - showing the trip as last saved on this phone.'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
    });
  });

  group('Share my location', () {
    testWidgets('is on for a running trip when the phone allows it', (tester) async {
      location.access = LocationAccess.granted;
      await openRunningTrip(tester);

      expect(tester.widget<SwitchListTile>(find.byKey(const Key('share-location-switch'))).value, isTrue);
      expect(api.locationBatches, hasLength(1));
    });

    testWidgets('turns itself off with the reason when permission is refused', (tester) async {
      await openRunningTrip(tester);

      expect(tester.widget<SwitchListTile>(find.byKey(const Key('share-location-switch'))).value, isFalse);
      expect(find.text('Location permission was not given, so your location is not being shared.'), findsOneWidget);
    });
  });
}
