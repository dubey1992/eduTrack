import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/add_student_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_student_repository.dart';

// A school admin is already scoped to their own school server-side, so this
// dialog skips the School picker entirely for them (see AddStudentDialog's
// `isSuperAdmin` branch) - using that role here keeps these tests focused on
// the fields every actor sees.
const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

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

Widget wrap({FakeStudentRepository? student}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
      studentRepositoryProvider.overrideWithValue(student ?? FakeStudentRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddStudentDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _selectClass(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Grade 8 A').last);
  await tester.pumpAndSettle();
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Arjun');
  await tester.enterText(find.widgetWithText(TextFormField, 'Last name'), 'Kumar');
  await tester.enterText(find.widgetWithText(TextFormField, 'Admission ID'), 'STU-0001');
  await _selectClass(tester);
  await tester.enterText(find.widgetWithText(TextFormField, 'Parent / Guardian'), 'Raj Kumar');
}

void main() {
  testWidgets('shows validation errors when required fields are left empty', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Student'));
    await tester.pumpAndSettle();

    // First name, last name, admission ID and guardian all share the same
    // "Required" validator message.
    expect(find.text('Required'), findsNWidgets(4));
    expect(find.text('Class is required'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeStudentRepository();
    await tester.pumpWidget(wrap(student: fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillRequiredFields(tester);
    await tester.tap(find.text('Save Student'));
    await tester.pumpAndSettle();

    expect(find.byType(AddStudentDialog), findsNothing);
    expect(find.text('Student admitted.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeStudentRepository(
      failCreateWith: const Failure(code: 'DUPLICATE_ADMISSION_NUMBER', message: 'Admission ID already in use.'),
    );
    await tester.pumpWidget(wrap(student: fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillRequiredFields(tester);
    await tester.tap(find.text('Save Student'));
    await tester.pumpAndSettle();

    expect(find.text('Admission ID already in use.'), findsOneWidget);
    expect(find.byType(AddStudentDialog), findsOneWidget);
  });
}
