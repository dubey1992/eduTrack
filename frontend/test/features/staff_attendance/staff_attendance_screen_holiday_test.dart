import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
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

const _holidayRegister = StaffAttendanceRegister(
  schoolId: 1,
  attendanceDate: '2026-11-10',
  submitted: false,
  holiday: HolidaySummary(id: 3, name: 'Diwali Break', type: HolidayType.religious),
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
  ],
);

Widget wrap(StaffAttendanceRegister register) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
      staffAttendanceRepositoryProvider.overrideWithValue(FakeStaffAttendanceRepository(register: register)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: StaffAttendanceScreen()),
    ),
  );
}

void main() {
  testWidgets('a holiday shows a banner and disables every input on the staff register', (tester) async {
    await tester.pumpWidget(wrap(_holidayRegister));
    await tester.pumpAndSettle();

    expect(find.text('Holiday: Diwali Break'), findsOneWidget);
    expect(find.text('Attendance is not marked on holidays. Pick another date to mark staff.'), findsOneWidget);
    expect(find.text('Not yet submitted'), findsNothing);
    expect(find.text('Mark All Present'), findsNothing);
    expect(find.text('Submit Attendance'), findsNothing);

    expect(find.text('EMP-001 · Priya Sharma'), findsOneWidget);
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.onSelected, isNull);
    }
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Check In')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Check Out')).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });
}
