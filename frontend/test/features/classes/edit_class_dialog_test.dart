import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/classes/presentation/edit_class_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_class_repository.dart';

const _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 3,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: [],
);

/// The dialog is opened via a real [showDialog] call (behind an "Open"
/// button) rather than placed directly as the page body - _submit() calls
/// Navigator.of(context).pop() on success, and without a real dialog route
/// on the stack that pop() would remove the whole page (Scaffold, SnackBar
/// and all) instead of just the dialog.
Widget wrap(FakeSchoolClassRepository fake) {
  return ProviderScope(
    overrides: [schoolClassRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const EditClassDialog(schoolClass: _schoolClass),
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
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(classes: [_schoolClass])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Grade / Class (e.g. Grade 8)'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('shows a validation error when the level is out of range', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(classes: [_schoolClass])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Level (0-12)'), '13');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a level between 0 and 12'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeSchoolClassRepository(classes: [_schoolClass]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Grade / Class (e.g. Grade 8)'), 'Grade 8A');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = await fake.list();
    expect(updated.single.name, 'Grade 8A');
    expect(find.byType(EditClassDialog), findsNothing);
    expect(find.text('Class updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSchoolClassRepository(
      classes: [_schoolClass],
      failUpdateWith: const Failure(code: 'VALIDATION_ERROR', message: 'That class already exists for this year.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Grade / Class (e.g. Grade 8)'), 'Grade 8A');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That class already exists for this year.'), findsOneWidget);
    expect(find.byType(EditClassDialog), findsOneWidget);
  });
}
