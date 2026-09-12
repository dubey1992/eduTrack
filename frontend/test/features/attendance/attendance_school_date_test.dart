import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/school_clock.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/attendance/presentation/attendance_screen.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';

/// The register opens on the school's day.
///
/// A teacher in Delhi marking attendance early in the morning is on a later
/// date than a UTC server, and a browser could be anywhere at all. The screen
/// must ask for - and allow - the school's today, not the device's.
final _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(
      id: 5,
      schoolClassId: 1,
      name: 'A',
      roomNumber: null,
      classTeacherId: 42,
      classTeacherName: 'Priya Sharma',
    ),
  ],
);

const _register = AttendanceRegister(
  classSectionId: 5,
  attendanceDate: '2026-09-17',
  submitted: false,
  students: [AttendanceRosterEntry(studentId: 1, name: 'Arjun Kumar', rollNumber: '1', status: null, remarks: null)],
);

/// A teacher whose school is a day ahead of the machine running this test.
AuthenticatedUser teacherAtSchoolDay(DateTime schoolWallClock) {
  return AuthenticatedUser(
    id: 42,
    name: 'Priya Sharma',
    email: 'priya@example.com',
    role: UserRole.teacher,
    clock: SchoolClock(
      timezone: 'Asia/Kolkata',
      schoolTimeAtAnchor: schoolWallClock,
      anchorUtc: DateTime.now().toUtc(),
    ),
  );
}

Widget wrap(AuthenticatedUser teacher, FakeAttendanceRepository attendance) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: teacher)),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      attendanceRepositoryProvider.overrideWithValue(attendance),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AttendanceScreen()),
    ),
  );
}

void main() {
  testWidgets('opens the register on the school date, not the device date', (tester) async {
    final attendance = FakeAttendanceRepository(register: _register);
    // Half past midnight on the 17th at the school.
    await tester.pumpWidget(wrap(teacherAtSchoolDay(DateTime(2026, 9, 17, 0, 30)), attendance));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    expect(attendance.lastRegisterDate, '2026-09-17');
  });

  testWidgets('shows the school date on the screen', (tester) async {
    final attendance = FakeAttendanceRepository(register: _register);
    await tester.pumpWidget(wrap(teacherAtSchoolDay(DateTime(2026, 9, 17, 0, 30)), attendance));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sep 17, 2026'), findsWidgets);
  });

  testWidgets('a school still on the previous day opens on that day', (tester) async {
    final attendance = FakeAttendanceRepository(register: _register);
    // Ten at night on the 15th - the server and much of the world have
    // already moved on to the 16th.
    await tester.pumpWidget(wrap(teacherAtSchoolDay(DateTime(2026, 9, 15, 22, 0)), attendance));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    expect(attendance.lastRegisterDate, '2026-09-15');
  });
}
