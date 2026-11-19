import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/family/data/models/family_bus.dart';
import 'package:edutrack_app/features/family/presentation/family_bus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart';

/// The Bus tab and following the bus (docs/parent-student-app.md, F4).
/// Scrolls the Bus list (not the child switcher above it) until [finder] is built.
Future<void> revealOnBus(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(of: find.byKey(const Key('family-bus')), matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the trip record (4.3)', () {
    test('is read by kind, with who marked each and where', () {
      final trip = FamilyBusTrip.fromJson({
        'id': 1,
        'direction': 'drop',
        'status': 'completed',
        'is_live': false,
        'timeline': [
          {'type': 'started', 'at': '14:00', 'stop_name': null, 'by': 'Sunil Rao', 'by_role': 'driver'},
          {
            'type': 'dropped',
            'at': '14:31',
            'stop_name': 'Sakal Nagar',
            'by': 'Asha Pillai',
            'by_role': 'transport office',
          },
        ],
      });

      expect(trip.marks.keys, ['started', 'dropped']);
      expect(trip.marks['dropped']!.proof, 'Marked by Asha Pillai (transport office) at Sakal Nagar');
      expect(trip.marks['started']!.proof, 'Marked by Sunil Rao (driver)');
    });

    test('an older server with no record gives none, not an error', () {
      final trip = FamilyBusTrip.fromJson({'id': 1, 'direction': 'pickup', 'status': 'in_progress'});

      expect(trip.marks, isEmpty);
      expect(const BusMark(at: '07:00').proof, isNull);
    });
  });

  group('the Bus tab', () {
    testWidgets('shows the route, the stop, the vehicle and the times', (tester) async {
      await pumpFamilyApp(tester, goTo: '/bus');

      expect(find.text('Baner Road'), findsOneWidget);
      expect(find.text('Sakal Nagar'), findsOneWidget);
      expect(find.text('Bus 3 · MH-12-AB-1234'), findsOneWidget);
      expect(find.text('Pick-up'), findsOneWidget);
    });

    testWidgets('today\'s trip is the child\'s own moments, with their times', (tester) async {
      await pumpFamilyApp(tester, goTo: '/bus');

      final pickup = find.byKey(const Key('family-trip-pickup'));
      expect(find.descendant(of: pickup, matching: find.text('Aarav boarded')), findsOneWidget);
      expect(find.descendant(of: pickup, matching: find.text('Reached Sakal Nagar')), findsOneWidget);
      expect(find.descendant(of: pickup, matching: find.text('Reached school')), findsOneWidget);
      // Trip proof (4.3): who marked the child on, and where.
      expect(
        find.descendant(of: pickup, matching: find.text('Marked by Ravi Kumar (attendant) at Sakal Nagar')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('family-trip-drop')), matching: find.text('Not started yet')),
        findsOneWidget,
      );
    });

    testWidgets('a child marked absent is shown as not boarding', (tester) async {
      final data = FakeFamilyRepository()..busValue = familyBus(live: false, riderStatus: 'absent');
      await pumpFamilyApp(tester, data: data, goTo: '/bus');

      expect(find.text('Did not board'), findsOneWidget);
      expect(find.text('Marked by Ravi Kumar (attendant) at Sakal Nagar'), findsOneWidget);
      expect(find.byKey(const Key('family-track-bus')), findsNothing);
    });

    testWidgets('a cancelled trip and a trip the child is not listed on say so', (tester) async {
      final data = FakeFamilyRepository()..busValue = familyBus(live: false, tripStatus: 'cancelled');
      await pumpFamilyApp(tester, data: data, goTo: '/bus');
      expect(find.textContaining('This trip was cancelled'), findsOneWidget);

      data.busValue = familyBus(live: false, onList: false);
      await tester.drag(find.byKey(const Key('family-bus')), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.textContaining('is not on this trip\'s list today'), findsOneWidget);
    });

    testWidgets('a child not on a school bus is told so', (tester) async {
      final data = FakeFamilyRepository()..busValue = null;
      await pumpFamilyApp(tester, data: data, goTo: '/bus');

      expect(find.text('Not on a school bus'), findsOneWidget);
    });

    testWidgets('the attendant\'s number shows only when the school allows it, and calls', (tester) async {
      final (_, _, opened) = await pumpFamilyApp(tester, goTo: '/bus');
      await revealOnBus(tester, find.byKey(const Key('family-call-transport')));
      expect(find.byKey(const Key('family-call-attendant')), findsNothing);

      await tester.tap(
        find.descendant(of: find.byKey(const Key('family-call-transport')), matching: find.byIcon(Icons.call_rounded)),
      );
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'tel:+912040001234');
    });

    testWidgets('with the school\'s permission the attendant can be called', (tester) async {
      final data = FakeFamilyRepository()..busValue = familyBus(withAttendant: true);
      await pumpFamilyApp(tester, data: data, goTo: '/bus');
      await revealOnBus(tester, find.byKey(const Key('family-call-attendant')));

      expect(find.text('Ravi Kumar'), findsOneWidget);
    });

    testWidgets('a failure says what went wrong and tries again', (tester) async {
      final data = FakeFamilyRepository()..failBusWith = Failure.network();
      await pumpFamilyApp(tester, data: data, goTo: '/bus');
      expect(find.text('No connection'), findsOneWidget);

      data.failBusWith = null;
      await tester.tap(find.byKey(const Key('family-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('family-bus-route')), findsOneWidget);
    });
  });

  group('following the bus', () {
    testWidgets('only a running trip the child is on offers the map', (tester) async {
      final data = FakeFamilyRepository()..busValue = familyBus(live: false);
      await pumpFamilyApp(tester, data: data, goTo: '/bus');

      expect(find.byKey(const Key('family-track-bus')), findsNothing);
    });

    testWidgets('the map says how far, how long and how many stops, in words', (tester) async {
      await pumpFamilyApp(tester, goTo: '/bus');
      await tester.tap(find.byKey(const Key('family-track-bus')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('family-bus-live')), findsOneWidget);
      expect(find.text('On its way to Sakal Nagar'), findsOneWidget);
      expect(find.text('about 4 minutes · 350 m away · 1 stop before yours'), findsOneWidget);
    });

    testWidgets('it asks again every 15 seconds, and stops once the trip is no longer theirs', (tester) async {
      final data = FakeFamilyRepository()..liveAnswers = [familyBusLive(), null];
      await pumpFamilyApp(tester, data: data, goTo: '/bus/live');
      expect(data.liveAsks, 1);

      await tester.pump(busRefreshInterval);
      await tester.pumpAndSettle();
      expect(data.liveAsks, 2);
      expect(find.textContaining('isn\'t on the road for Aarav now'), findsOneWidget);

      await tester.pump(busRefreshInterval * 2);
      expect(data.liveAsks, 2, reason: 'no more asking once the trip is over for them');
    });

    testWidgets('an old position warns that the bus may be out of signal', (tester) async {
      final data = FakeFamilyRepository()..liveAnswers = [familyBusLive(stale: true)];
      await pumpFamilyApp(tester, data: data, goTo: '/bus/live');

      expect(find.textContaining('may be out of signal'), findsOneWidget);
    });

    testWidgets('a stop already reached says so instead of a distance', (tester) async {
      final data = FakeFamilyRepository()..liveAnswers = [familyBusLive(reached: true)];
      await pumpFamilyApp(tester, data: data, goTo: '/bus/live');

      expect(find.text('The bus has been to Sakal Nagar'), findsOneWidget);
      expect(find.textContaining('m away'), findsNothing);
    });
  });
}
