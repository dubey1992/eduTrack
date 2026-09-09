import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
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
}
