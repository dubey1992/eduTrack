import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/subjects/presentation/edit_subject_dialog.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_department_repository.dart';
import '../../support/fake_subject_repository.dart';
import '../../support/fake_user_repository.dart';

const _department = Department(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: null,
  hodName: null,
);

const _subject = Subject(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: 2,
  departmentName: 'Mathematics',
  code: 'MAT',
  name: 'Mathematics',
  minClassLevel: 7,
  maxClassLevel: 10,
  leadTeacherId: null,
  leadTeacherName: null,
);

/// The dialog is opened via a real [showDialog] call (behind an "Open"
/// button) rather than placed directly as the page body - _submit() calls
/// Navigator.of(context).pop() on success, and without a real dialog route
/// on the stack that pop() would remove the whole page (Scaffold, SnackBar
/// and all) instead of just the dialog.
Widget wrap(FakeSubjectRepository fake) {
  return ProviderScope(
    overrides: [
      subjectRepositoryProvider.overrideWithValue(fake),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository(departments: const [_department])),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const EditSubjectDialog(subject: _subject),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when the code is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeSubjectRepository(subjects: [_subject])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Code (e.g. MAT)'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Code is required'), findsOneWidget);
  });

  testWidgets('shows a validation error when the max class level is below the min', (tester) async {
    await tester.pumpWidget(wrap(FakeSubjectRepository(subjects: [_subject])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Min class level'), '11');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('The max class level must be at or above the min class level.'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeSubjectRepository(subjects: [_subject]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Subject name'), 'Advanced Mathematics');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = await fake.list();
    expect(updated.single.name, 'Advanced Mathematics');
    expect(find.byType(EditSubjectDialog), findsNothing);
    expect(find.text('Subject updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSubjectRepository(
      subjects: [_subject],
      failUpdateWith: const Failure(code: 'VALIDATION_ERROR', message: 'That subject code is already in use.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Subject name'), 'Advanced Mathematics');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That subject code is already in use.'), findsOneWidget);
    expect(find.byType(EditSubjectDialog), findsOneWidget);
  });
}
