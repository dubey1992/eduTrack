import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/students/application/student_enrollment_notifier.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/models/student_enrollment.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/student_history_dialog.dart';
import 'package:edutrack_app/features/students/presentation/student_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/session_users.dart';

StudentEnrollment enrollment({
  int id = 1,
  String year = '2026-27',
  String className = 'Grade 7',
  String? section = 'A',
  String? roll = '4',
  EnrollmentStatus status = EnrollmentStatus.studying,
}) {
  return StudentEnrollment(
    id: id,
    academicYearId: id,
    academicYearName: year,
    className: className,
    sectionName: section,
    rollNumber: roll,
    status: status,
  );
}

const _student = Student(
  id: 7,
  schoolId: 1,
  schoolName: 'Test School',
  classSectionId: 3,
  classSectionName: 'Grade 7 A',
  admissionNumber: 'ADM-1',
  firstName: 'Aarav',
  lastName: 'Sharma',
  name: 'Aarav Sharma',
  rollNumber: '4',
  guardianName: 'Meera Sharma',
  guardianMobile: null,
  address: null,
  status: StudentStatus.active,
);

Widget wrap(FakeStudentRepository fake, {UserRole role = UserRole.schoolAdmin, Widget? child}) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
    ],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body:
            child ??
            Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const StudentHistoryDialog(student: _student),
                ),
                child: const Text('Open'),
              ),
            ),
      ),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the model', () {
    test('reads a class and section together', () {
      expect(enrollment().classLabel, 'Grade 7 A');
    });

    test('reads the class alone once the section is gone', () {
      expect(enrollment(section: null).classLabel, 'Grade 7');
    });

    test('parses a row, including a status it has not seen before', () {
      final row = StudentEnrollment.fromJson({
        'id': 2,
        'academic_year_id': 5,
        'academic_year_name': '2025-26',
        'class_name': 'Grade 6',
        'section_name': null,
        'roll_number': null,
        'status': 'something_new',
      });

      expect(row.classLabel, 'Grade 6');
      expect(row.rollNumber, isNull);
      // An unknown status must not crash a screen that only wants to print
      // where the child was.
      expect(row.status, EnrollmentStatus.studying);
    });

    test('names each outcome in words a school would use', () {
      expect(EnrollmentStatus.retained.label, 'Repeated the year');
      expect(EnrollmentStatus.graduated.label, 'Graduated');
    });
  });

  group('the notifier', () {
    test('loads one student history', () async {
      final fake = FakeStudentRepository(
        enrollments: [
          enrollment(),
          enrollment(id: 2, year: '2025-26'),
        ],
      );
      final container = ProviderContainer(
        overrides: [studentRepositoryProvider.overrideWithValue(fake)],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      final sub = container.listen(studentEnrollmentsProvider(7), (_, _) {});
      addTearDown(sub.close);

      final rows = await container.read(studentEnrollmentsProvider(7).future);

      expect(rows.map((row) => row.academicYearName), ['2026-27', '2025-26']);
      expect(fake.calls, contains('enrollments'));
    });
  });

  group('the dialog', () {
    testWidgets('lists each year with its class, roll number and outcome', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(
        enrollments: [
          enrollment(),
          enrollment(id: 2, year: '2025-26', className: 'Grade 6', roll: '11', status: EnrollmentStatus.promoted),
        ],
      );

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      expect(find.text('History · Aarav Sharma'), findsOneWidget);
      expect(find.text('Grade 7 A'), findsOneWidget);
      expect(find.text('2026-27 · Roll 4'), findsOneWidget);
      expect(find.text('Grade 6 A'), findsOneWidget);
      expect(find.text('Promoted'), findsOneWidget);
      expect(find.text('Studying'), findsOneWidget);
    });

    testWidgets('a year with no roll number reads as the year alone', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(enrollments: [enrollment(roll: null)])));
      await open(tester);

      expect(find.text('2026-27'), findsOneWidget);
    });

    testWidgets('says why a student has no years yet', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(enrollments: const [])));
      await open(tester);

      expect(find.textContaining('No years recorded yet'), findsOneWidget);
    });

    testWidgets('offers a retry when the history cannot be loaded', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(
        failWith: {'enrollments': const Failure(code: 'SERVER_ERROR', message: 'History is unavailable.')},
      );

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      expect(find.text('History is unavailable.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('the students list', () {
    testWidgets('offers the history to a teacher, and nothing else', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(students: [_student]);

      await tester.pumpWidget(wrap(fake, role: UserRole.teacher, child: const StudentListScreen()));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Class history'), findsOneWidget);
      expect(find.text('View'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
    });

    testWidgets('an administrator gets the history beside the other actions', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(students: [_student]);

      await tester.pumpWidget(wrap(fake, child: const StudentListScreen()));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Class history'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);
    });

    testWidgets('opening the history from the list shows that student', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(students: [_student], enrollments: [enrollment()]);

      await tester.pumpWidget(wrap(fake, child: const StudentListScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Class history'));
      await tester.pumpAndSettle();

      expect(find.text('History · Aarav Sharma'), findsOneWidget);
      // The row behind the dialog carries the same class, so this is scoped.
      expect(find.descendant(of: find.byType(StudentHistoryDialog), matching: find.text('Grade 7 A')), findsOneWidget);
    });
  });
}
