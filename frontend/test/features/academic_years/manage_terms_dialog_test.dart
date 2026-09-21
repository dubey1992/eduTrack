import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_term_repository.dart';
import 'package:edutrack_app/features/academic_years/presentation/manage_terms_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_term_repository.dart';

/// The dialog is always opened through a real [showDialog] behind an "Open"
/// button: its submit pops the route, and without a dialog on the stack that
/// pop would tear down the Scaffold and the SnackBar with it.
Widget wrap(FakeAcademicTermRepository fake, {bool canManage = true}) {
  return ProviderScope(
    overrides: [academicTermRepositoryProvider.overrideWithValue(fake)],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => ManageTermsDialog(year: fakeYear(), canManage: canManage),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Types a date into the picker's input mode rather than tapping a day cell,
/// so the test does not depend on what today is or on the calendar's layout.
Future<void> pickDate(WidgetTester tester, String label, String text) async {
  await tester.tap(find.text(label), warnIfMissed: false);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();

  final field = find.descendant(of: find.byType(InputDatePickerFormField), matching: find.byType(TextFormField));
  await tester.enterText(field, text);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  group('the list of terms', () {
    testWidgets('shows each term with its order and dates', (tester) async {
      final fake = FakeAcademicTermRepository(
        terms: [
          fakeTerm(id: 1, name: 'Term 1', sequenceNumber: 1),
          fakeTerm(
            id: 2,
            name: 'Term 2',
            sequenceNumber: 2,
            startDate: DateTime(2026, 9, 1),
            endDate: DateTime(2027, 3, 31),
          ),
        ],
      );

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      expect(find.text('Terms · 2026-27'), findsOneWidget);
      expect(find.text('Term 1'), findsOneWidget);
      expect(find.text('Term 2'), findsOneWidget);
    });

    testWidgets('says what to do when the year has no terms', (tester) async {
      await tester.pumpWidget(wrap(FakeAcademicTermRepository()));
      await open(tester);

      expect(find.textContaining('No terms in this year yet'), findsOneWidget);
    });

    testWidgets('offers a retry when the terms cannot be loaded', (tester) async {
      final fake = FakeAcademicTermRepository(
        failWith: {'listForYear': const Failure(code: 'SERVER_ERROR', message: 'Terms are unavailable.')},
      );

      await tester.pumpWidget(wrap(fake));
      await open(tester);

      expect(find.text('Terms are unavailable.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('who may change them', () {
    testWidgets('a manager gets Add, Edit and Delete', (tester) async {
      await tester.pumpWidget(wrap(FakeAcademicTermRepository(terms: [fakeTerm()])));
      await open(tester);

      expect(find.text('Add Term'), findsOneWidget);
      expect(find.byTooltip('Edit term'), findsOneWidget);
      expect(find.byTooltip('Delete term'), findsOneWidget);
    });

    testWidgets('a read-only role sees the terms and none of the actions', (tester) async {
      await tester.pumpWidget(wrap(FakeAcademicTermRepository(terms: [fakeTerm()]), canManage: false));
      await open(tester);

      expect(find.text('Term 1'), findsOneWidget);
      expect(find.text('Add Term'), findsNothing);
      expect(find.byTooltip('Edit term'), findsNothing);
      expect(find.byTooltip('Delete term'), findsNothing);
    });
  });

  group('adding a term', () {
    testWidgets('requires a name', (tester) async {
      await tester.pumpWidget(wrap(FakeAcademicTermRepository()));
      await open(tester);
      await tester.tap(find.text('Add Term'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('requires an order of 1 or more', (tester) async {
      await tester.pumpWidget(wrap(FakeAcademicTermRepository()));
      await open(tester);
      await tester.tap(find.text('Add Term'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Term 1)'), 'Term 1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Order within the year'), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid order (1 or more)'), findsOneWidget);
    });

    testWidgets('asks for both dates before it will save', (tester) async {
      final fake = FakeAcademicTermRepository();
      await tester.pumpWidget(wrap(fake));
      await open(tester);
      await tester.tap(find.text('Add Term'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Term 1)'), 'Term 1');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Both a start and end date are required.'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));
    });

    testWidgets('refuses an end date that is not after the start', (tester) async {
      final fake = FakeAcademicTermRepository();
      await tester.pumpWidget(wrap(fake));
      await open(tester);
      await tester.tap(find.text('Add Term'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Term 1)'), 'Term 1');
      await pickDate(tester, 'Start date', '08/31/2026');
      await pickDate(tester, 'End date', '04/01/2026');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('The end date must be after the start date.'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));
    });

    testWidgets('saves, confirms and closes', (tester) async {
      final fake = FakeAcademicTermRepository();
      await tester.pumpWidget(wrap(fake));
      await open(tester);
      await tester.tap(find.text('Add Term'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Term 1)'), 'Term 1');
      await pickDate(tester, 'Start date', '04/01/2026');
      await pickDate(tester, 'End date', '08/31/2026');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('create'));
      expect(find.text('Term added.'), findsOneWidget);
      expect(find.text('Add Term'), findsOneWidget, reason: 'the form closed, the terms dialog stayed');
    });

    testWidgets('shows a validation error from the server on the field it belongs to', (tester) async {
      final fake = FakeAcademicTermRepository(
        failWith: {
          'create': const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The given data was invalid.',
            details: {
              'errors': {
                'start_date': ['These dates overlap Term 1 (2026-04-01 to 2026-08-31).'],
              },
            },
          ),
        },
      );
      await tester.pumpWidget(wrap(fake));
      await open(tester);
      await tester.tap(find.text('Add Term'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Term 1)'), 'Term 2');
      await pickDate(tester, 'Start date', '08/01/2026');
      await pickDate(tester, 'End date', '12/31/2026');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('These dates overlap Term 1 (2026-04-01 to 2026-08-31).'), findsOneWidget);
      // The banner does not repeat what the field already says.
      expect(find.text('The given data was invalid.'), findsNothing);
    });

    testWidgets('a failure with no field named is shown as a banner', (tester) async {
      final fake = FakeAcademicTermRepository(
        failWith: {
          'create': const Failure(code: 'MODULE_DISABLED', message: 'Academics is switched off for this school.'),
        },
      );
      await tester.pumpWidget(wrap(fake));
      await open(tester);
      await tester.tap(find.text('Add Term'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Name (e.g. Term 1)'), 'Term 1');
      await pickDate(tester, 'Start date', '04/01/2026');
      await pickDate(tester, 'End date', '08/31/2026');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Academics is switched off for this school.'), findsOneWidget);
    });
  });

  group('editing and deleting', () {
    testWidgets('the edit form opens with the term already in it', (tester) async {
      await tester.pumpWidget(wrap(FakeAcademicTermRepository(terms: [fakeTerm(name: 'Term 1')])));
      await open(tester);

      await tester.tap(find.byTooltip('Edit term'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Term'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Term 1'), findsOneWidget);
    });

    testWidgets('deleting asks first, and does nothing if the answer is no', (tester) async {
      final fake = FakeAcademicTermRepository(terms: [fakeTerm(name: 'Term 1')]);
      await tester.pumpWidget(wrap(fake));
      await open(tester);

      await tester.tap(find.byTooltip('Delete term'));
      await tester.pumpAndSettle();
      expect(find.text('Remove term?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.calls, isNot(contains('delete')));
      expect(find.text('Term 1'), findsOneWidget);
    });

    testWidgets('confirming the delete removes it and says so', (tester) async {
      final fake = FakeAcademicTermRepository(terms: [fakeTerm(name: 'Term 1')]);
      await tester.pumpWidget(wrap(fake));
      await open(tester);

      await tester.tap(find.byTooltip('Delete term'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('delete'));
      expect(find.text('Term 1 was removed.'), findsOneWidget);
    });

    testWidgets('a refused delete shows the reason and keeps the term', (tester) async {
      final fake = FakeAcademicTermRepository(
        terms: [fakeTerm(name: 'Term 1')],
        failWith: {
          'delete': const Failure(
            code: 'HAS_DEPENDENT_RECORDS',
            message: 'This term still has assessments filed under it.',
          ),
        },
      );
      await tester.pumpWidget(wrap(fake));
      await open(tester);

      await tester.tap(find.byTooltip('Delete term'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This term still has assessments filed under it.'), findsOneWidget);
      expect(find.text('Term 1'), findsOneWidget);
    });
  });
}
