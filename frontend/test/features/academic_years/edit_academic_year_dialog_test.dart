import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/academic_years/presentation/edit_academic_year_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';

final _year = AcademicYear(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: '2026-27',
  startDate: DateTime(2026, 4, 1),
  endDate: DateTime(2027, 3, 31),
  isCurrent: false,
);

/// The dialog is opened via a real [showDialog] call (behind an "Open"
/// button) rather than placed directly as the page body - _submit() calls
/// Navigator.of(context).pop() on success, and without a real dialog route
/// on the stack that pop() would remove the whole page (Scaffold, SnackBar
/// and all) instead of just the dialog.
Widget wrap(FakeAcademicYearRepository fake) {
  return ProviderScope(
    overrides: [academicYearRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditAcademicYearDialog(academicYear: _year),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when the name is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeAcademicYearRepository(years: [_year])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('shows a validation error when the end date is not after the start date', (tester) async {
    await tester.pumpWidget(wrap(FakeAcademicYearRepository(years: [_year])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('End date'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final dateField = find.descendant(of: find.byType(InputDatePickerFormField), matching: find.byType(TextFormField));
    await tester.enterText(dateField, '01/01/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('The end date must be after the start date.'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeAcademicYearRepository(years: [_year]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), '2026-27 Revised');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = await fake.list();
    expect(updated.single.name, '2026-27 Revised');
    expect(find.byType(EditAcademicYearDialog), findsNothing);
    expect(find.text('Academic year updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeAcademicYearRepository(
      years: [_year],
      failUpdateWith: const Failure(code: 'VALIDATION_ERROR', message: 'That academic year name is already in use.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. 2026-27)'), '2026-27 Revised');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That academic year name is already in use.'), findsOneWidget);
    expect(find.byType(EditAcademicYearDialog), findsOneWidget);
  });
}
