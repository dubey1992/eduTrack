import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/subjects/presentation/add_subject_dialog.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_subject_repository.dart';
import '../../support/fake_user_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

const _department = Department(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: null,
  hodName: null,
);

/// A SCHOOL_ADMIN actor is used throughout so the dialog's school picker
/// (only shown for a SUPER_ADMIN) never renders. A department is always
/// seeded since the Department field is required to submit.
///
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
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddSubjectDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _selectDepartment(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Department'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mathematics').last);
  await tester.pumpAndSettle();
}

Future<void> _fillValidForm(WidgetTester tester) async {
  await _selectDepartment(tester);
  await tester.enterText(find.widgetWithText(TextFormField, 'Code (e.g. MAT)'), 'MAT');
  await tester.enterText(find.widgetWithText(TextFormField, 'Subject name'), 'Mathematics');
  await tester.enterText(find.widgetWithText(TextFormField, 'Min class level'), '7');
  await tester.enterText(find.widgetWithText(TextFormField, 'Max class level'), '10');
}

void main() {
  testWidgets('shows a validation error when required fields are left empty', (tester) async {
    await tester.pumpWidget(wrap(FakeSubjectRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Department is required'), findsOneWidget);
    expect(find.text('Code is required'), findsOneWidget);
    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('shows a validation error when the max class level is below the min', (tester) async {
    await tester.pumpWidget(wrap(FakeSubjectRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _selectDepartment(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Code (e.g. MAT)'), 'MAT');
    await tester.enterText(find.widgetWithText(TextFormField, 'Subject name'), 'Mathematics');
    await tester.enterText(find.widgetWithText(TextFormField, 'Min class level'), '10');
    await tester.enterText(find.widgetWithText(TextFormField, 'Max class level'), '7');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('The max class level must be at or above the min class level.'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeSubjectRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillValidForm(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final created = await fake.list();
    expect(created, hasLength(1));
    expect(created.single.code, 'MAT');
    expect(created.single.minClassLevel, 7);
    expect(created.single.maxClassLevel, 10);
    expect(find.byType(AddSubjectDialog), findsNothing);
    expect(find.text('Subject created.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSubjectRepository(
      failCreateWith: const Failure(code: 'VALIDATION_ERROR', message: 'That subject code is already in use.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillValidForm(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That subject code is already in use.'), findsOneWidget);
    expect(find.byType(AddSubjectDialog), findsOneWidget);
  });
}
