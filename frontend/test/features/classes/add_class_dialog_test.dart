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
  await _pick(tester, 'Academic year', '2026-27');
  await tester.enterText(find.widgetWithText(TextFormField, 'Class name (e.g. Class 8 or LKG)'), 'Class 8');
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String label, String item) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
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
    expect(find.text('Choose which year this is'), findsOneWidget);
  });

  testWidgets('the year is worked out from the class name', (tester) async {
    final fake = FakeSchoolClassRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _pick(tester, 'Academic year', '2026-27');

    await tester.enterText(find.widgetWithText(TextFormField, 'Class name (e.g. Class 8 or LKG)'), 'LKG');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'LKG'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await fake.list()).single.level, -1);
  });

  testWidgets('a name that says nothing asks for the year', (tester) async {
    final fake = FakeSchoolClassRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _pick(tester, 'Academic year', '2026-27');

    await tester.enterText(find.widgetWithText(TextFormField, 'Class name (e.g. Class 8 or LKG)'), 'Rose');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Choose which year this is'), findsOneWidget);
    expect(await fake.list(), isEmpty);

    await _pick(tester, 'Year', 'Class 3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await fake.list()).single.level, 3);
  });

  testWidgets('a year picked by hand stays when the name changes', (tester) async {
    final fake = FakeSchoolClassRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _pick(tester, 'Academic year', '2026-27');

    await tester.enterText(find.widgetWithText(TextFormField, 'Class name (e.g. Class 8 or LKG)'), 'Rose');
    await _pick(tester, 'Year', 'UKG');
    await tester.enterText(find.widgetWithText(TextFormField, 'Class name (e.g. Class 8 or LKG)'), 'Class 4');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await fake.list()).single.level, 0);
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
    expect(created.single.name, 'Class 8');
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
