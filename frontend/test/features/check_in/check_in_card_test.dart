import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/check_in/presentation/check_in_card.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_check_in_repository.dart';
import '../../support/my_trip_fixtures.dart';

/// The check-in card at the top of Today (docs/staff-check-in.md).
void main() {
  late FakeLocationSource location;

  setUp(() => location = FakeLocationSource());

  Future<void> show(WidgetTester tester, FakeCheckInRepository repository, {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          checkInRepositoryProvider.overrideWithValue(repository),
          locationSourceProvider.overrideWithValue(location),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.teacherLight(),
          home: const Scaffold(body: SingleChildScrollView(child: CheckInCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('before arriving it asks for a check-in', (tester) async {
    await show(tester, FakeCheckInRepository());

    expect(find.text('Check in to start your day'), findsOneWidget);
    expect(find.byKey(const Key('check-in-button')), findsOneWidget);
    expect(find.byKey(const Key('check-out-button')), findsNothing);
    expect(find.textContaining('within 100 m of school'), findsOneWidget);
  });

  testWidgets('checking in sends where the phone is and shows the time, late and present', (tester) async {
    final repository = FakeCheckInRepository();
    await show(tester, repository);

    await tester.tap(find.byKey(const Key('check-in-button')));
    await tester.pumpAndSettle();

    expect(repository.sentFrom, isNotNull);
    expect(repository.sentFrom!.accuracy, 8);
    expect(find.text('Checked in at 9:05 AM'), findsOneWidget);
    expect(find.text('Checked in at 9:05 AM.'), findsOneWidget, reason: 'the confirmation');
    expect(find.text('Present'), findsOneWidget);
    expect(find.byKey(const Key('check-in-late')), findsOneWidget);
    expect(find.byKey(const Key('check-out-button')), findsOneWidget);
  });

  testWidgets('checking out shows the hours, and offers to check out again', (tester) async {
    final repository = FakeCheckInRepository(
      day: attendanceDay(status: StaffAttendanceStatus.present, checkIn: '09:05'),
    );
    await show(tester, repository);

    await tester.tap(find.byKey(const Key('check-out-button')));
    await tester.pumpAndSettle();

    expect(find.text('9:05 AM – 4:05 PM · 7h 0m'), findsOneWidget);
    expect(find.text('Check out again'), findsOneWidget);
  });

  testWidgets("the server's refusal is shown on the card, which stays as it was", (tester) async {
    final repository = FakeCheckInRepository(
      refuseWith: const Failure(
        code: 'OUTSIDE_SCHOOL',
        message: 'You are 300 m from school. Check in when you are within 100 m.',
      ),
    );
    await show(tester, repository);

    await tester.tap(find.byKey(const Key('check-in-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('check-in-problem')), findsOneWidget);
    expect(find.text('You are 300 m from school. Check in when you are within 100 m.'), findsOneWidget);
    expect(find.byKey(const Key('check-in-button')), findsOneWidget);
  });

  for (final (access, words) in [
    (LocationAccess.denied, 'Allow it and try again'),
    (LocationAccess.deniedForever, "phone's settings"),
    (LocationAccess.serviceOff, 'switched off'),
  ]) {
    testWidgets('without location ($access) it says what to do and sends nothing', (tester) async {
      location.access = access;
      final repository = FakeCheckInRepository();
      await show(tester, repository);

      await tester.tap(find.byKey(const Key('check-in-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining(words), findsOneWidget);
      expect(repository.sentFrom, isNull);
    });
  }

  testWidgets('marked absent by the office, it says so and still offers a check-in', (tester) async {
    await show(
      tester,
      FakeCheckInRepository(day: attendanceDay(status: StaffAttendanceStatus.absent, markedBySomeoneElse: true)),
    );

    expect(find.text('Marked absent today'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
    expect(find.byKey(const Key('check-in-button')), findsOneWidget);
  });

  testWidgets("a school without its pin says why, with no button", (tester) async {
    await show(
      tester,
      FakeCheckInRepository(day: attendanceDay(blockedReason: 'Your school has not set its location yet.')),
    );

    expect(find.text('Check-in unavailable'), findsOneWidget);
    expect(find.text('Your school has not set its location yet.'), findsOneWidget);
    expect(find.byKey(const Key('check-in-button')), findsNothing);
  });

  for (final (label, day) in [
    ('the school marks staff in the office', attendanceDay(enabled: false)),
    ('the school is closed', attendanceDay(isOpen: false)),
    ('the person is on leave', attendanceDay(onLeave: true)),
  ]) {
    testWidgets('it is not there at all when $label', (tester) async {
      await show(tester, FakeCheckInRepository(day: day));

      expect(find.byKey(const Key('check-in-card')), findsNothing);
    });
  }

  testWidgets('an account with no staff record is told so, without a retry that cannot help', (tester) async {
    await show(
      tester,
      FakeCheckInRepository(
        failLoadWith: const Failure(code: 'NO_STAFF_RECORD', message: 'Checking in is for members of a school.'),
      ),
    );

    expect(find.byKey(const Key('check-in-no-staff-record')), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('if the day cannot be loaded it offers a retry', (tester) async {
    final repository = FakeCheckInRepository(failLoadWith: Failure.network());
    await show(tester, repository);

    expect(find.byKey(const Key('check-in-load-failed')), findsOneWidget);

    repository.failLoadWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('check-in-button')), findsOneWidget);
  });

  testWidgets('a second tap while the first is on its way sends nothing more', (tester) async {
    final repository = FakeCheckInRepository()..checkInGate = Completer<void>();
    await show(tester, repository);

    await tester.tap(find.byKey(const Key('check-in-button')));
    await tester.pump();
    expect(find.text('Finding your location…'), findsOneWidget);

    await tester.tap(find.byKey(const Key('check-in-button')), warnIfMissed: false);
    await tester.pump();

    repository.checkInGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.checkIns, 1);
    expect(location.positionsTaken, 1);
  });

  testWidgets('reads in dark mode', (tester) async {
    await show(tester, FakeCheckInRepository(), theme: AppTheme.teacherDark());

    expect(find.byKey(const Key('check-in-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
