import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
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

void main() {
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
