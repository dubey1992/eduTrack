import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
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
import '../../support/viewed_year_overrides.dart';

const _admin = AuthenticatedUser(
  id: 2,
  name: 'Anita',
  email: 'anita@example.com',
  role: UserRole.schoolAdmin,
  schoolId: 1,
);

AcademicYear _year(int id, String name, int start, {bool current = false}) => AcademicYear(
  id: id,
  schoolId: 1,
  schoolName: 'Sunrise',
  name: name,
  startDate: DateTime(start, 4, 1),
  endDate: DateTime(start + 1, 3, 31),
  isCurrent: current,
);

SchoolClass _class(int id, int yearId, String name, int sectionId, {bool current = false}) => SchoolClass(
  id: id,
  schoolId: 1,
  schoolName: 'Sunrise',
  academicYearId: yearId,
  academicYearName: null,
  name: name,
  level: 5,
  isCurrentYear: current,
  sections: [
    ClassSection(
      id: sectionId,
      schoolClassId: id,
      name: 'A',
      roomNumber: null,
      classTeacherId: null,
      classTeacherName: null,
    ),
  ],
);

const _register = AttendanceRegister(classSectionId: 1, attendanceDate: '2026-03-31', submitted: false, students: []);

Future<void> _pump(WidgetTester tester, AcademicYear viewed) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
        schoolClassRepositoryProvider.overrideWithValue(
          FakeSchoolClassRepository(classes: [_class(1, 1, 'Class 5', 11), _class(2, 2, 'Class 6', 22, current: true)]),
        ),
        attendanceRepositoryProvider.overrideWithValue(FakeAttendanceRepository(register: _register)),
        ...viewedYearIs(viewed),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AttendanceScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Student Attendance follows the top bar's year (decided 2026-11-05).
void main() {
  testWidgets('a past year opens on its last day and offers that year sections', (tester) async {
    await _pump(tester, _year(1, '2025-26', 2025));

    expect(find.text('03/31/2026'), findsOneWidget);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();

    expect(find.text('Class 5 A'), findsWidgets);
    expect(find.text('Class 6 A'), findsNothing);
  });

  testWidgets('a year that has not begun says so, and offers no date', (tester) async {
    await _pump(tester, _year(3, '2099-00', 2099));

    expect(find.byKey(const Key('attendance-year-not-begun')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('attendance-date'))).onPressed, isNull);
  });
}
