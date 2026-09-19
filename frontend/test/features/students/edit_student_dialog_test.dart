import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/students/presentation/edit_student_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_class_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/fake_transport_repository.dart';

final _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 1, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

const _student = Student(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 1,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'STU-0042',
  firstName: 'Arjun',
  lastName: 'Kumar',
  name: 'Arjun Kumar',
  rollNumber: '12',
  guardianName: 'Raj Kumar',
  guardianMobile: '9876543210',
  address: null,
  status: StudentStatus.active,
  guardianEmail: 'raj@example.com',
  studentMobile: '+91 9123456789',
  studentEmail: 'arjun@example.com',
);

Widget wrap(FakeStudentRepository fake) {
  return ProviderScope(
    overrides: [
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      studentRepositoryProvider.overrideWithValue(fake),
      transportRepositoryProvider.overrideWithValue(FakeTransportRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const EditStudentDialog(student: _student),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when guardian name is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Parent / Guardian'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
    expect(find.byType(EditStudentDialog), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeStudentRepository(students: [_student]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Roll number (optional)'), '13');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(EditStudentDialog), findsNothing);
    expect(find.text('Student updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeStudentRepository(
      students: [_student],
      failUpdateWith: const Failure(code: 'STUDENT_UPDATE_FAILED', message: 'Could not update student.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Roll number (optional)'), '13');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not update student.'), findsOneWidget);
    expect(find.byType(EditStudentDialog), findsOneWidget);
  });

  group('contact details', () {
    String fieldText(WidgetTester tester, String label) {
      return tester.widget<TextFormField>(find.widgetWithText(TextFormField, label)).controller!.text;
    }

    testWidgets('are shown with what the student already has', (tester) async {
      await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'Parent email (optional)'), 'raj@example.com');
      // The number field holds the local part; the dial code is picked beside it.
      expect(fieldText(tester, 'Student mobile (optional)'), '9123456789');
      expect(fieldText(tester, 'Student email (optional)'), 'arjun@example.com');
    });

    testWidgets('an email that is not one is refused', (tester) async {
      final fake = FakeStudentRepository(students: [_student]);
      await tester.pumpWidget(wrap(fake));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Student email (optional)'), 'arjun.example.com');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(fake.lastUpdate, isNull);
      expect(find.byType(EditStudentDialog), findsOneWidget);
    });

    testWidgets('changed details reach the repository, and a cleared one is sent as nothing', (tester) async {
      final fake = FakeStudentRepository(students: [_student]);
      await tester.pumpWidget(wrap(fake));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Parent email (optional)'), 'raj.kumar@example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Student mobile (optional)'), '9000000000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Student email (optional)'), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(EditStudentDialog), findsNothing);
      expect(fake.lastUpdate!['guardian_email'], 'raj.kumar@example.com');
      expect(fake.lastUpdate!['student_mobile'], '+91 9000000000');
      expect(fake.lastUpdate!['student_email'], isNull);
    });
  });
}
