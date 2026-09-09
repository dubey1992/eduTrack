import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/classes/presentation/edit_section_dialog.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_class_repository.dart';
import '../../support/fake_user_repository.dart';

const _section = ClassSection(
  id: 1,
  schoolClassId: 1,
  name: 'A',
  roomNumber: 'Room 204',
  classTeacherId: null,
  classTeacherName: null,
);

const _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 3,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: [_section],
);

/// The dialog is opened via a real [showDialog] call (behind an "Open"
/// button) rather than placed directly as the page body - _submit() calls
/// Navigator.of(context).pop() on success, and without a real dialog route
/// on the stack that pop() would remove the whole page (Scaffold, SnackBar
/// and all) instead of just the dialog.
Widget wrap(FakeSchoolClassRepository fake) {
  return ProviderScope(
    overrides: [
      schoolClassRepositoryProvider.overrideWithValue(fake),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const EditSectionDialog(schoolId: 1, section: _section),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when the section name is cleared', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(classes: [_schoolClass])));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Section (e.g. A)'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Section name is required'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeSchoolClassRepository(classes: [_schoolClass]);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Room number (optional)'), 'Room 301');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final classes = await fake.list();
    expect(classes.single.sections.single.roomNumber, 'Room 301');
    expect(find.byType(EditSectionDialog), findsNothing);
    expect(find.text('Section updated.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeSchoolClassRepository(
      classes: [_schoolClass],
      failUpdateSectionWith: const Failure(code: 'VALIDATION_ERROR', message: 'That section already exists.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Room number (optional)'), 'Room 301');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('That section already exists.'), findsOneWidget);
    expect(find.byType(EditSectionDialog), findsOneWidget);
  });
}
