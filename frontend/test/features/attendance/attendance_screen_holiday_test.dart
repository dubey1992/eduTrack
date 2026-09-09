import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/attendance/presentation/attendance_screen.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
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

const _holidayRegister = AttendanceRegister(
  classSectionId: 5,
  attendanceDate: '2026-08-15',
  submitted: false,
  holiday: HolidaySummary(id: 1, name: 'Independence Day', type: HolidayType.national),
  students: [
    AttendanceRosterEntry(studentId: 1, name: 'Arjun Kumar', rollNumber: '1', status: null, remarks: null),
    AttendanceRosterEntry(studentId: 2, name: 'Sara Ali', rollNumber: '2', status: null, remarks: null),
  ],
);

Widget wrap(AttendanceRegister register) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      attendanceRepositoryProvider.overrideWithValue(FakeAttendanceRepository(register: register)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AttendanceScreen()),
    ),
  );
}

void main() {
  testWidgets('a holiday shows a banner and locks the register instead of the submit row', (tester) async {
    await tester.pumpWidget(wrap(_holidayRegister));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    expect(find.text('Holiday: Independence Day'), findsOneWidget);
    expect(find.text('Attendance is not marked on holidays. Pick another date to mark this class.'), findsOneWidget);
    expect(find.text('Not yet submitted'), findsNothing);
    expect(find.text('Mark All Present'), findsNothing);
    expect(find.text('Submit Attendance'), findsNothing);

    // The roster is still listed, but every status chip is disabled.
    expect(find.text('Arjun Kumar'), findsOneWidget);
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.onSelected, isNull);
    }
  });
}
