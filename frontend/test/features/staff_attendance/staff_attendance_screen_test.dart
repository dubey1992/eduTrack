import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/check_in_event.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_status.dart';
import 'package:edutrack_app/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:edutrack_app/features/staff_attendance/presentation/staff_attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_staff_attendance_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

const _register = StaffAttendanceRegister(
  schoolId: 1,
  attendanceDate: '2026-09-08',
  submitted: false,
  staff: [
    StaffRosterEntry(
      staffProfileId: 1,
      employeeId: 'EMP-001',
      name: 'Priya Sharma',
      departmentName: 'Mathematics',
      status: null,
      checkIn: null,
      checkOut: null,
      workingHours: null,
      remarks: null,
    ),
    StaffRosterEntry(
      staffProfileId: 2,
      employeeId: 'EMP-002',
      name: 'Rahul Verma',
      departmentName: 'Science',
      status: null,
      checkIn: null,
      checkOut: null,
      workingHours: null,
      remarks: null,
    ),
  ],
);

/// A day nobody has marked, where the fingerprint reader already has times
/// for one of the two (docs/biometric.md, B3).
const _registerFromDevice = StaffAttendanceRegister(
  schoolId: 1,
  attendanceDate: '2026-09-08',
  submitted: false,
  staff: [
    StaffRosterEntry(
      staffProfileId: 1,
      employeeId: 'EMP-001',
      name: 'Priya Sharma',
      departmentName: 'Mathematics',
      status: null,
      checkIn: '09:02',
      checkOut: '17:31',
      workingHours: '8h 29m',
      remarks: null,
      timesFromDevice: true,
    ),
    StaffRosterEntry(
      staffProfileId: 2,
      employeeId: 'EMP-002',
      name: 'Rahul Verma',
      departmentName: 'Science',
      status: null,
      checkIn: null,
      checkOut: null,
      workingHours: null,
      remarks: null,
    ),
  ],
);

/// A day a punch marked, with nobody's name on it, where the check-in is
/// after the first period (docs/biometric.md, B5).
const _registerMarkedByDevice = StaffAttendanceRegister(
  schoolId: 1,
  attendanceDate: '2026-09-08',
  submitted: true,
  staff: [
    StaffRosterEntry(
      staffProfileId: 1,
      employeeId: 'EMP-001',
      name: 'Priya Sharma',
      departmentName: 'Mathematics',
      status: StaffAttendanceStatus.present,
      checkIn: '09:47',
      checkOut: '17:31',
      workingHours: '7h 44m',
      remarks: null,
      markedByDevice: true,
      late: true,
    ),
    StaffRosterEntry(
      staffProfileId: 2,
      employeeId: 'EMP-002',
      name: 'Rahul Verma',
      departmentName: 'Science',
      status: StaffAttendanceStatus.present,
      checkIn: '08:55',
      checkOut: '17:02',
      workingHours: '8h 7m',
      remarks: null,
    ),
  ],
);

/// Already submitted, with every staff member already marked - the "correct
/// a past day" flow, as opposed to the still-blank register above.
const _submittedRegister = StaffAttendanceRegister(
  schoolId: 1,
  attendanceDate: '2026-09-08',
  submitted: true,
  staff: [
    StaffRosterEntry(
      staffProfileId: 1,
      employeeId: 'EMP-001',
      name: 'Priya Sharma',
      departmentName: 'Mathematics',
      status: StaffAttendanceStatus.present,
      checkIn: null,
      checkOut: null,
      workingHours: null,
      remarks: null,
    ),
    StaffRosterEntry(
      staffProfileId: 2,
      employeeId: 'EMP-002',
      name: 'Rahul Verma',
      departmentName: 'Science',
      status: StaffAttendanceStatus.present,
      checkIn: null,
      checkOut: null,
      workingHours: null,
      remarks: null,
    ),
  ],
);

Widget wrap({FakeStaffAttendanceRepository? staffAttendance}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
      staffAttendanceRepositoryProvider.overrideWithValue(
        staffAttendance ?? FakeStaffAttendanceRepository(register: _register),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: StaffAttendanceScreen()),
    ),
  );
}

const _registerCheckedInFromApp = StaffAttendanceRegister(
  schoolId: 1,
  attendanceDate: '2026-09-08',
  submitted: true,
  staff: [
    StaffRosterEntry(
      staffProfileId: 1,
      employeeId: 'EMP-001',
      name: 'Priya Sharma',
      departmentName: 'Mathematics',
      status: StaffAttendanceStatus.present,
      checkIn: '08:20',
      checkOut: null,
      workingHours: null,
      remarks: null,
      checkedInFromApp: true,
    ),
  ],
);

const _appEvents = [
  CheckInEvent(
    id: 11,
    staffProfileId: 1,
    name: 'Priya Sharma',
    employeeId: 'EMP-001',
    departmentName: 'Mathematics',
    isCheckIn: true,
    time: '08:20',
    distanceMetres: 34,
  ),
  CheckInEvent(
    id: 12,
    staffProfileId: 1,
    name: 'Priya Sharma',
    employeeId: 'EMP-001',
    departmentName: 'Mathematics',
    isCheckIn: false,
    time: '16:05',
    distanceMetres: 41,
  ),
];

void main() {
  group('checking in from the app (docs/staff-check-in.md)', () {
    Future<void> show(WidgetTester tester, FakeStaffAttendanceRepository repository) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(wrap(staffAttendance: repository));
      await tester.pumpAndSettle();
    }

    testWidgets('a time that came from the app says so on the register', (tester) async {
      await show(tester, FakeStaffAttendanceRepository(register: _registerCheckedInFromApp));

      expect(find.byKey(const ValueKey('from-app-1')), findsOneWidget);
      expect(find.text('From the app'), findsOneWidget);
      expect(find.text('Marked from the device'), findsNothing);
    });

    testWidgets('a day marked by hand says nothing about the app', (tester) async {
      await show(tester, FakeStaffAttendanceRepository(register: _submittedRegister));

      expect(find.text('From the app'), findsNothing);
    });

    testWidgets("the day's app check-ins are listed in order, with the distance from school", (tester) async {
      await show(
        tester,
        FakeStaffAttendanceRepository(register: _registerCheckedInFromApp)..checkInEvents = _appEvents,
      );

      expect(find.byKey(const Key('check-in-log')), findsOneWidget);
      final checkedIn = tester.getTopLeft(find.byKey(const ValueKey('check-in-event-11'))).dy;
      final checkedOut = tester.getTopLeft(find.byKey(const ValueKey('check-in-event-12'))).dy;
      expect(checkedIn, lessThan(checkedOut));
      expect(find.text('8:20 AM'), findsOneWidget);
      expect(find.text('4:05 PM'), findsOneWidget);
      expect(find.text('34 m'), findsOneWidget);
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.text('Checked out'), findsOneWidget);
    });

    testWidgets('a day without app check-ins says so', (tester) async {
      await show(tester, FakeStaffAttendanceRepository(register: _register));

      expect(find.byKey(const Key('check-in-log-empty')), findsOneWidget);
    });

    testWidgets('a log that cannot be loaded offers a retry and leaves the register alone', (tester) async {
      await show(tester, FakeStaffAttendanceRepository(register: _register)..failCheckInsWith = Failure.network());

      expect(find.text('The app check-ins could not be loaded.'), findsOneWidget);
      expect(find.text('EMP-001 · Priya Sharma'), findsOneWidget, reason: 'the register still shows');
    });
  });

  group('a day a punch marked', () {
    testWidgets('it says the device marked it, not a person', (tester) async {
      // A row with nobody's name on it is not the same as a day somebody
      // decided, and whoever opens this should know which it is before
      // leaving it alone.
      await tester.pumpWidget(wrap(staffAttendance: FakeStaffAttendanceRepository(register: _registerMarkedByDevice)));
      await tester.pumpAndSettle();

      expect(find.text('Marked from the device'), findsOneWidget);
      expect(find.text('From the device'), findsNothing);
    });

    testWidgets('a late arrival is badged, and is still Present', (tester) async {
      await tester.pumpWidget(wrap(staffAttendance: FakeStaffAttendanceRepository(register: _registerMarkedByDevice)));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'Late'), findsOneWidget);
      // One badge, on the one who was late - not on their colleague.
      expect(find.text('09:47'), findsOneWidget);
      expect(find.text('08:55'), findsOneWidget);
    });

    testWidgets('a day somebody marked by hand says nothing about a device', (tester) async {
      await tester.pumpWidget(wrap(staffAttendance: FakeStaffAttendanceRepository(register: _submittedRegister)));
      await tester.pumpAndSettle();

      expect(find.text('Marked from the device'), findsNothing);
      expect(find.widgetWithText(Chip, 'Late'), findsNothing);
    });
  });

  group('times a fingerprint reader filled in', () {
    testWidgets('they are shown, and said to have come from a device', (tester) async {
      // Whoever sets the status is about to save these as the register's
      // own, so they should know they did not type them.
      await tester.pumpWidget(wrap(staffAttendance: FakeStaffAttendanceRepository(register: _registerFromDevice)));
      await tester.pumpAndSettle();

      expect(find.text('09:02'), findsOneWidget);
      expect(find.text('17:31'), findsOneWidget);
      expect(find.text('From the device'), findsOneWidget);
    });

    testWidgets('a day with no punches says nothing of the sort', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('From the device'), findsNothing);
    });

    testWidgets('they can still be changed, because the status is a human decision', (tester) async {
      await tester.pumpWidget(wrap(staffAttendance: FakeStaffAttendanceRepository(register: _registerFromDevice)));
      await tester.pumpAndSettle();

      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '09:02')).onPressed, isNotNull);
    });
  });

  testWidgets('shows the roster immediately for a school admin, no school picker needed', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('EMP-001 · Priya Sharma'), findsOneWidget);
    expect(find.text('EMP-002 · Rahul Verma'), findsOneWidget);
    expect(find.text('Not yet submitted'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'School'), findsNothing);
  });

  testWidgets('marking all present enables submit and submitting shows confirmation', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final submitButtonFinder = find.widgetWithText(FilledButton, 'Submit Attendance');
    expect(tester.widget<FilledButton>(submitButtonFinder).onPressed, isNull);

    await tester.tap(find.text('Mark All Present'));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(submitButtonFinder).onPressed, isNotNull);

    await tester.tap(submitButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Attendance submitted.'), findsOneWidget);
  });

  testWidgets('shows the error state with a Retry button when the register fails to load', (tester) async {
    final fake = FakeStaffAttendanceRepository(
      register: _register,
      failRegisterWith: const Failure(code: 'SERVER_ERROR', message: 'Could not load the staff attendance register.'),
    );
    await tester.pumpWidget(wrap(staffAttendance: fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load the staff attendance register.'), findsOneWidget);
    final retryButtonFinder = find.widgetWithText(OutlinedButton, 'Retry');
    expect(retryButtonFinder, findsOneWidget);
    // AsyncNotifier retries a failing build a few times on its own before
    // settling, so only the general "it was called" shape is asserted here,
    // not an exact count.
    final callCountBeforeRetry = fake.registerCallCount;
    expect(callCountBeforeRetry, greaterThan(0));

    await tester.tap(retryButtonFinder);
    await tester.pumpAndSettle();

    // Still fails on retry - the error view (and its Retry button) stays up,
    // and tapping it did trigger at least one more attempt.
    expect(find.text('Could not load the staff attendance register.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    expect(fake.registerCallCount, greaterThan(callCountBeforeRetry));
  });

  testWidgets('correcting an already-submitted day changes a status and resubmits it as an update', (tester) async {
    final fake = FakeStaffAttendanceRepository(register: _submittedRegister);
    await tester.pumpWidget(wrap(staffAttendance: fake));
    await tester.pumpAndSettle();

    expect(find.text('Submitted'), findsOneWidget);
    final updateButtonFinder = find.widgetWithText(FilledButton, 'Update Attendance');
    expect(updateButtonFinder, findsOneWidget);
    // Every staff member already has a mark, so the button starts out enabled.
    expect(tester.widget<FilledButton>(updateButtonFinder).onPressed, isNotNull);

    // Correct Priya Sharma (the first roster row) from Present to Absent.
    await tester.tap(find.byTooltip('Absent').first);
    await tester.pumpAndSettle();

    await tester.tap(updateButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Attendance updated.'), findsOneWidget);
    expect(fake.lastUpdatePayload, isNotNull);
    final records = fake.lastUpdatePayload!['records'] as List<Map<String, dynamic>>;
    expect(records.firstWhere((r) => r['staff_profile_id'] == 1)['status'], 'absent');
    expect(records.firstWhere((r) => r['staff_profile_id'] == 2)['status'], 'present');
  });
}
