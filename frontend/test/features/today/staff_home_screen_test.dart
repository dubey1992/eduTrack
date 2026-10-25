import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/check_in/data/models/my_attendance_day.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/today/presentation/staff_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_check_in_repository.dart';
import '../../support/my_trip_fixtures.dart';
import '../../support/session_users.dart';

/// Home for the school's staff who do not teach (docs/staff-check-in.md).
void main() {
  Future<void> show(WidgetTester tester, MyAttendanceDay day) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository(day: day)),
          locationSourceProvider.overrideWithValue(FakeLocationSource()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.accountant, name: 'Ravi Kumar')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.teacherLight(),
          home: const Scaffold(body: StaffHomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("greets them with the school's date and the check-in card", (tester) async {
    await show(tester, notCheckedIn());

    expect(find.text('Good day, Ravi'), findsOneWidget);
    expect(find.text('Monday, October 26, 2026'), findsOneWidget);
    expect(find.byKey(const Key('check-in-button')), findsOneWidget);
    expect(find.byKey(const Key('staff-home-no-check-in')), findsNothing);
  });

  testWidgets('says plainly that the rest is on the website for now', (tester) async {
    await show(tester, notCheckedIn());

    expect(find.byKey(const Key('staff-home-website-note')), findsOneWidget);
  });

  for (final (label, day, title) in [
    ('the school is closed', attendanceDay(isOpen: false), 'No school today'),
    ('they are on leave', attendanceDay(onLeave: true), 'You are on leave today'),
    ('the school marks staff in the office', attendanceDay(enabled: false), 'Attendance is marked in the office'),
  ]) {
    testWidgets('when $label it says why there is no check-in', (tester) async {
      await show(tester, day);

      expect(find.byKey(const Key('check-in-card')), findsNothing);
      expect(find.text(title), findsOneWidget);
    });
  }

  testWidgets('checking in from Home works the same as from Today', (tester) async {
    await show(tester, notCheckedIn());

    await tester.tap(find.byKey(const Key('check-in-button')));
    await tester.pumpAndSettle();

    expect(find.text('Checked in at 9:05 AM'), findsOneWidget);
  });
}
