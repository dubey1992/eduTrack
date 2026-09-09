import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/presentation/add_academic_year_dialog.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

/// A SCHOOL_ADMIN actor is used throughout so the dialog's school picker
/// (only shown for a SUPER_ADMIN) never renders - keeping these tests
/// focused on the fields every actor sees.
///
/// The dialog is opened via a real [showDialog] call (behind an "Open"
/// button) rather than placed directly as the page body - the dialog's
/// _submit() calls Navigator.of(context).pop() on success, and without a
/// real dialog route on the stack that pop() would remove the whole page
/// (Scaffold, SnackBar and all) instead of just the dialog.
Widget wrap(FakeAcademicYearRepository fake) {
  return ProviderScope(
    overrides: [
      academicYearRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddAcademicYearDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

/// Picks [text] (formatted MM/DD/YYYY) via the date picker's input-entry
/// mode rather than tapping calendar day cells - deterministic regardless of
/// "today"'s date and avoids ambiguity with day-number text elsewhere.
Future<void> _pickDate(WidgetTester tester, String label, String text) async {
  // warnIfMissed: false - the floating label sits under InkWell/Material ink
  // layers, so the finder's exact render object is technically obscured even
  // though the tap correctly opens the picker every time.
  await tester.tap(find.text(label), warnIfMissed: false);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();

  final dateField = find.descendant(of: find.byType(InputDatePickerFormField), matching: find.byType(TextFormField));
  await tester.enterText(dateField, text);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a validation error when the name is left empty', (tester) async {
    await tester.pumpWidget(wrap(FakeAcademicYearRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('shows a validation error when no dates are picked', (tester) async {
    await tester.pumpWidget(wrap(FakeAcademicYearRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), '2026-27');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Both a start and end date are required.'), findsOneWidget);
  });

  testWidgets('shows a validation error when the end date is not after the start date', (tester) async {
    await tester.pumpWidget(wrap(FakeAcademicYearRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), '2026-27');
    await _pickDate(tester, 'Start date', '09/15/2026');
    await _pickDate(tester, 'End date', '09/01/2026');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('The end date must be after the start date.'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeAcademicYearRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), '2026-27');
    await _pickDate(tester, 'Start date', '04/01/2026');
    await _pickDate(tester, 'End date', '03/31/2027');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final created = await fake.list();
    expect(created, hasLength(1));
    expect(created.single.name, '2026-27');
    expect(find.byType(AddAcademicYearDialog), findsNothing);
    expect(find.text('Academic year created.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeAcademicYearRepository(
      failCreateWith: const Failure(code: 'VALIDATION_ERROR', message: 'That academic year name is already in use.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), '2026-27');
    await _pickDate(tester, 'Start date', '04/01/2026');
    await _pickDate(tester, 'End date', '03/31/2027');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That academic year name is already in use.'), findsOneWidget);
    expect(find.byType(AddAcademicYearDialog), findsOneWidget);
  });
}
