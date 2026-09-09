import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
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

/// Already submitted, with every student already marked - the "correct a
/// past day" flow, as opposed to the still-blank register above.
const _submittedRegister = AttendanceRegister(
  classSectionId: 5,
  attendanceDate: '2026-09-08',
  submitted: true,
  students: [
    AttendanceRosterEntry(
      studentId: 1,
      name: 'Arjun Kumar',
      rollNumber: '1',
      status: AttendanceStatus.present,
      remarks: null,
    ),
    AttendanceRosterEntry(
      studentId: 2,
      name: 'Sara Ali',
      rollNumber: '2',
      status: AttendanceStatus.present,
      remarks: null,
    ),
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

  testWidgets('shows the error state with a Retry button when the register fails to load', (tester) async {
    final fake = FakeAttendanceRepository(
      register: _register,
      failRegisterWith: const Failure(code: 'SERVER_ERROR', message: 'Could not load the attendance register.'),
    );
    await tester.pumpWidget(wrap(attendance: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    expect(find.text('Could not load the attendance register.'), findsOneWidget);
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
    expect(find.text('Could not load the attendance register.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    expect(fake.registerCallCount, greaterThan(callCountBeforeRetry));
  });

  testWidgets('correcting an already-submitted day changes a status and resubmits it as an update', (tester) async {
    final fake = FakeAttendanceRepository(register: _submittedRegister);
    await tester.pumpWidget(wrap(attendance: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    expect(find.text('Submitted'), findsOneWidget);
    final updateButtonFinder = find.widgetWithText(FilledButton, 'Update Attendance');
    expect(updateButtonFinder, findsOneWidget);
    // Every student already has a mark, so the button starts out enabled.
    expect(tester.widget<FilledButton>(updateButtonFinder).onPressed, isNotNull);

    // Correct Arjun Kumar (the first roster row) from Present to Absent.
    await tester.tap(find.byTooltip('Absent').first);
    await tester.pumpAndSettle();

    await tester.tap(updateButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Attendance updated.'), findsOneWidget);
    expect(fake.lastUpdatePayload, isNotNull);
    expect(fake.lastUpdatePayload!['class_section_id'], 5);
    final records = fake.lastUpdatePayload!['records'] as List<Map<String, dynamic>>;
    expect(records.firstWhere((r) => r['student_id'] == 1)['status'], 'absent');
    expect(records.firstWhere((r) => r['student_id'] == 2)['status'], 'present');
  });
}
