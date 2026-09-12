import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/trip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const _manager = AuthenticatedUser(id: 30, name: 'Mohan', email: 'mohan@example.com', role: UserRole.transportManager);
const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

Widget wrap(FakeTransportRepository fake, {AuthenticatedUser actor = _manager}) {
  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: TripScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pickGreenPark(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Route'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bus 04 - Green Park').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('prompts for a route, then shows the start controls when nothing is running', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark], ridersForNewTrip: [arjunTripRider, meeraTripRider]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Pick a route to see its trip for today.'), findsOneWidget);
    expect(find.text('No trips have been run yet.'), findsOneWidget);

    await _pickGreenPark(tester);

    expect(find.text('No trip in progress for this route.'), findsOneWidget);
    expect(find.text('Start Trip'), findsOneWidget);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Drop'), findsOneWidget);
  });

  testWidgets('starting a trip shows the live panel with KPIs, stops, riders and the timeline', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark], ridersForNewTrip: [arjunTripRider, meeraTripRider]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    await _pickGreenPark(tester);

    await tester.tap(find.text('Start Trip'));
    await tester.pumpAndSettle();

    expect(fake.lastCall!['op'], 'startTrip');
    expect(find.text('En Route'), findsWidgets);
    expect(find.textContaining('Driver: Sanjay Patel'), findsOneWidget);
    expect(find.text('Students'), findsWidgets);
    expect(find.text('Stops Left'), findsOneWidget);
    expect(find.text('1. Lake View'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Reached'), findsNWidgets(2));
    expect(find.text('Arjun Kumar · Grade 8 A'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Board'), findsNWidgets(2));
    expect(find.text('Trip started with 2 students expected'), findsOneWidget);
    expect(find.text('End Trip'), findsOneWidget);
    expect(find.text('Cancel Trip'), findsOneWidget);
    // The history list picked up the new trip too.
    expect(find.text('No trips have been run yet.'), findsNothing);
  });

  testWidgets('reaching a stop, boarding, dropping and ending update the panel', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    await _pickGreenPark(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reached').first);
    await tester.pumpAndSettle();
    expect(find.text('Reached Lake View.'), findsOneWidget);
    expect(find.text('Last stop reached: Lake View'), findsOneWidget);
    expect(find.text('Bus reached Lake View'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Board').first);
    await tester.pumpAndSettle();
    expect(fake.lastCall, {'op': 'updateRider', 'trip_id': 1, 'student_id': 7, 'status': 'boarded'});
    expect(find.text('Arjun Kumar boarded at Lake View'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Drop'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Drop'));
    await tester.pumpAndSettle();
    expect(find.text('Dropped'), findsWidgets);

    await tester.ensureVisible(find.text('End Trip'));
    await tester.tap(find.text('End Trip'));
    await tester.pumpAndSettle();
    expect(find.text('End trip?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'End Trip').last);
    await tester.pumpAndSettle();

    expect(fake.lastCall!['op'], 'endTrip');
    expect(find.text('Trip completed.'), findsOneWidget);
    expect(find.text('Last trip completed.'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Board'), findsNothing);
  });

  testWidgets('ending with a student on board shows the server error and keeps the trip running', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    await _pickGreenPark(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Board').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('End Trip'));
    await tester.tap(find.text('End Trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'End Trip').last);
    await tester.pumpAndSettle();

    expect(find.text('1 student is still on board. Drop them off before ending the trip.'), findsOneWidget);
    expect(find.text('End Trip'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Drop'), findsOneWidget);
  });

  testWidgets('the rider actions stay in place but go disabled while a confirm dialog is open', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    await _pickGreenPark(tester);

    await tester.ensureVisible(find.text('End Trip'));
    await tester.tap(find.text('End Trip'));
    await tester.pumpAndSettle();

    expect(find.text('End trip?'), findsOneWidget);
    // The column behind the dialog must not disappear - the buttons are only disabled.
    expect(find.widgetWithText(FilledButton, 'Board'), findsNWidgets(2));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Board').first).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reached').first).onPressed, isNull);

    // Backing out re-enables them without any snackbar.
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Board').first).onPressed, isNotNull);
    expect(find.text('En Route'), findsWidgets);
  });

  testWidgets('marking a rider absent and cancelling the trip', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    await _pickGreenPark(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Absent').first);
    await tester.pumpAndSettle();
    expect(find.text('Arjun Kumar marked absent'), findsOneWidget);

    await tester.ensureVisible(find.text('Cancel Trip'));
    await tester.tap(find.text('Cancel Trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Trip'));
    await tester.pumpAndSettle();

    expect(fake.lastCall!['op'], 'cancelTrip');
    expect(find.text('Last trip cancelled.'), findsOneWidget);
    expect(find.text('Start Trip'), findsOneWidget);
  });

  testWidgets('a teacher can follow a running trip but gets no controls', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark], trips: [greenParkTrip]);
    await tester.pumpWidget(wrap(fake, actor: _teacher));
    await tester.pumpAndSettle();
    await _pickGreenPark(tester);

    expect(find.text('En Route'), findsWidgets);
    expect(find.text('Arjun Kumar · Grade 8 A'), findsOneWidget);
    expect(find.text('Start Trip'), findsNothing);
    expect(find.text('End Trip'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reached'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Board'), findsNothing);
  });

  testWidgets('a start failure such as a non-working day is shown as a snackbar', (tester) async {
    useDesktop(tester);
    final fake = FakeTransportRepository(routes: [greenPark]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    await _pickGreenPark(tester);

    fake.failWith = const Failure(
      code: 'TRIP_ON_NON_WORKING_DAY',
      message: 'Trips do not run on weekends or holidays.',
    );
    await tester.tap(find.text('Start Trip'));
    await tester.pumpAndSettle();

    expect(find.text('Trips do not run on weekends or holidays.'), findsOneWidget);
    expect(find.text('No trip in progress for this route.'), findsOneWidget);
  });

  testWidgets('the history table lists trips and View opens the read-only detail', (tester) async {
    useDesktop(tester);
    final finished = greenParkTrip.copyWith(status: TripStatus.completed, endedAt: '2026-09-10T08:10:00.000000Z');
    final fake = FakeTransportRepository(routes: [greenPark], trips: [finished]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Bus 04 - Green Park'), findsWidgets);
    expect(find.text('Completed'), findsOneWidget);

    await tester.ensureVisible(find.text('View'));
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Trip details'), findsOneWidget);
    // The dialog is narrower than the desktop breakpoint, so riders render as cards.
    expect(find.text('Arjun Kumar'), findsOneWidget);
    expect(find.text('1. Lake View · Grade 8 A'), findsOneWidget);
    expect(find.text('Meera Singh'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Board'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reached'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Trip details'), findsNothing);
  });
}
