import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/classes/presentation/add_class_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

final _year = AcademicYear(
  id: 3,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: '2026-27',
  startDate: DateTime(2026, 4, 1),
  endDate: DateTime(2027, 3, 31),
  isCurrent: true,
);

/// A SCHOOL_ADMIN actor is used throughout so the dialog's school picker
/// (only shown for a SUPER_ADMIN) never renders. An academic year is always
/// seeded since the Academic year field is required to submit.
///
/// The dialog is opened via a real [showDialog] call (behind an "Open"
/// button) rather than placed directly as the page body - _submit() calls
/// Navigator.of(context).pop() on success, and without a real dialog route
/// on the stack that pop() would remove the whole page (Scaffold, SnackBar
/// and all) instead of just the dialog.
Widget wrap(FakeSchoolClassRepository fake) {
  return ProviderScope(
    overrides: [
      schoolClassRepositoryProvider.overrideWithValue(fake),
      academicYearRepositoryProvider.overrideWithValue(FakeAcademicYearRepository(years: [_year])),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddClassDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Academic year'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('2026-27').last);
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextFormField, 'Grade / Class (e.g. Grade 8)'), 'Grade 8');
  await tester.enterText(find.widgetWithText(TextFormField, 'Level (0-12)'), '8');
}

void main() {
  testWidgets('shows a validation error when required fields are left empty', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Academic year is required'), findsOneWidget);
    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('shows a validation error when the level is out of range', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Academic year'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-27').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Grade / Class (e.g. Grade 8)'), 'Grade 8');
    await tester.enterText(find.widgetWithText(TextFormField, 'Level (0-12)'), '15');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a level between 0 and 12'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeSchoolClassRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillValidForm(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final created = await fake.list();
    expect(created, hasLength(1));
    expect(created.single.name, 'Grade 8');
    expect(created.single.level, 8);
    expect(find.byType(AddClassDialog), findsNothing);
    expect(find.text('Class created.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSchoolClassRepository(
      failCreateWith: const Failure(code: 'VALIDATION_ERROR', message: 'That class already exists for this year.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await _fillValidForm(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That class already exists for this year.'), findsOneWidget);
    expect(find.byType(AddClassDialog), findsOneWidget);
  });
}
