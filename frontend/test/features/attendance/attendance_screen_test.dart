import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
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

const _teacher = AuthenticatedUser(id: 42, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

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
  attendanceDate: '2026-09-08',
  submitted: false,
  students: [
    AttendanceRosterEntry(studentId: 1, name: 'Arjun Kumar', rollNumber: '1', status: null, remarks: null),
    AttendanceRosterEntry(studentId: 2, name: 'Sara Ali', rollNumber: '2', status: null, remarks: null),
  ],
);

Widget wrap({FakeAttendanceRepository? attendance}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      attendanceRepositoryProvider.overrideWithValue(attendance ?? FakeAttendanceRepository(register: _register)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AttendanceScreen()),
    ),
  );
}

void main() {
  testWidgets('a teacher only sees the class sections they teach', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();

    expect(find.text('Grade 8 A').hitTestable(), findsWidgets);
  });

  testWidgets('selecting a class and marking all present enables submit and shows the register', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    expect(find.text('Arjun Kumar'), findsOneWidget);
    expect(find.text('Sara Ali'), findsOneWidget);
    expect(find.text('Not yet submitted'), findsOneWidget);

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
