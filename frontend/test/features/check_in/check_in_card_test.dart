import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/check_in/data/models/my_attendance_day.dart';
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
    expect(find.byKey(const Key('check-out-confirm')), findsOneWidget);
    expect(find.textContaining('You checked in at 9:05 AM'), findsOneWidget);

    await tester.tap(find.byKey(const Key('check-out-confirm-button')));
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

  group('edge cases', () {
    testWidgets('a check-out can be called off, and then nothing is sent', (tester) async {
      final repository = FakeCheckInRepository(
        day: attendanceDay(status: StaffAttendanceStatus.present, checkIn: '09:05'),
      );
      await show(tester, repository);

      await tester.tap(find.byKey(const Key('check-out-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('check-out-cancel')));
      await tester.pumpAndSettle();

      expect(repository.sentFrom, isNull);
      expect(location.positionsTaken, 0, reason: 'not even the location is asked for');
      expect(find.text('Checked in at 9:05 AM'), findsOneWidget);
    });

    testWidgets('checking out again says the time will change', (tester) async {
      await show(
        tester,
        FakeCheckInRepository(
          day: attendanceDay(status: StaffAttendanceStatus.present, checkIn: '09:05', checkOut: '16:05'),
        ),
      );

      await tester.tap(find.byKey(const Key('check-out-button')));
      await tester.pumpAndSettle();

      expect(find.text('Check out again?'), findsOneWidget);
      expect(find.textContaining('The last check-out is the one that counts'), findsOneWidget);
    });

    testWidgets('location switched off comes with the button that turns it on', (tester) async {
      location.access = LocationAccess.serviceOff;
      await show(tester, FakeCheckInRepository());

      await tester.tap(find.byKey(const Key('check-in-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('check-in-open-settings')));
      await tester.pumpAndSettle();

      expect(find.text('Turn on location'), findsOneWidget);
      expect(location.locationSettingsOpened, 1);
      expect(location.appSettingsOpened, 0);
    });

    testWidgets("location refused for good opens the app's settings", (tester) async {
      location.access = LocationAccess.deniedForever;
      await show(tester, FakeCheckInRepository());

      await tester.tap(find.byKey(const Key('check-in-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('check-in-open-settings')));
      await tester.pumpAndSettle();

      expect(location.appSettingsOpened, 1);
    });

    testWidgets('a refusal from the server has no settings button to offer', (tester) async {
      await show(
        tester,
        FakeCheckInRepository(
          refuseWith: const Failure(code: 'OUTSIDE_SCHOOL', message: 'You are 300 m from school.'),
        ),
      );

      await tester.tap(find.byKey(const Key('check-in-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('check-in-open-settings')), findsNothing);
    });

    testWidgets('without signal it says that nothing was recorded', (tester) async {
      await show(tester, FakeCheckInRepository(refuseWith: Failure.network()));

      await tester.tap(find.byKey(const Key('check-in-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('No connection, so nothing was recorded'), findsOneWidget);
      expect(find.byKey(const Key('check-in-button')), findsOneWidget);
    });

    testWidgets('the phone tells the server whether the fix is mocked and how old it is', (tester) async {
      location
        ..mocked = true
        ..fixAge = const Duration(seconds: 30);
      final repository = FakeCheckInRepository();
      await show(tester, repository);

      await tester.tap(find.byKey(const Key('check-in-button')));
      await tester.pumpAndSettle();

      expect(repository.sentFrom!.isMocked, isTrue);
      expect(DateTime.now().difference(repository.sentFrom!.takenAt!).inSeconds, inInclusiveRange(29, 40));
    });

    testWidgets('half-day leave says so and still offers the check-in', (tester) async {
      await show(tester, FakeCheckInRepository(day: attendanceDay(halfDayLeave: true)));

      expect(find.text('Half-day leave today'), findsOneWidget);
      expect(find.byKey(const Key('check-in-button')), findsOneWidget);
    });

    testWidgets('a day they forgot to check out of is mentioned, with who can fix it', (tester) async {
      await show(
        tester,
        FakeCheckInRepository(
          day: attendanceDay(
            unfinishedDay: UnfinishedDay(date: DateTime(2026, 10, 23), checkIn: '08:45'),
          ),
        ),
      );

      expect(find.byKey(const Key('check-in-unfinished')), findsOneWidget);
      expect(find.textContaining('You did not check out on Fri, Oct 23 (checked in 8:45 AM)'), findsOneWidget);
    });

    testWidgets('a day the office changed after the check-in says so', (tester) async {
      await show(
        tester,
        FakeCheckInRepository(
          day: attendanceDay(status: StaffAttendanceStatus.halfDay, checkIn: '09:05', markedBySomeoneElse: true),
        ),
      );

      expect(find.byKey(const Key('check-in-office-changed')), findsOneWidget);
      expect(find.text('Half Day'), findsOneWidget);
    });
  });

  testWidgets('reads in dark mode', (tester) async {
    await show(tester, FakeCheckInRepository(), theme: AppTheme.teacherDark());

    expect(find.byKey(const Key('check-in-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
