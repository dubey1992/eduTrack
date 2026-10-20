import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/application/school_week_provider.dart';
import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:edutrack_app/features/timetable/data/models/period.dart';
import 'package:edutrack_app/features/timetable/data/period_repository.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/manage_periods_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_period_repository.dart';

const _period = Period(id: 1, schoolId: 1, periodNumber: 1, startTime: '08:30', endTime: '09:15');

// Opened via a real showDialog route (rather than placed directly as the
// Scaffold body) so its nested Add/Edit Period sub-dialog behaves under a
// real Navigator, matching every other AlertDialog-based dialog test in this
// app (see add_school_dialog_test.dart etc.).
Widget wrap(FakePeriodRepository fake, {int? schoolId, String week = '1111100'}) {
  return ProviderScope(
    overrides: [
      periodRepositoryProvider.overrideWithValue(fake),
      // The school's own week, which decides whether there is a half day to
      // put periods on at all.
      schoolWeekProvider(schoolId).overrideWithValue(WorkingWeek.fromApiValue(week)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => ManagePeriodsDialog(schoolId: schoolId),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openManagePeriods(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _openAddPeriod(WidgetTester tester) async {
  await tester.tap(find.text('Add Period'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a validation error for an invalid period number', (tester) async {
    await tester.pumpWidget(wrap(FakePeriodRepository()));
    await _openManagePeriods(tester);
    await _openAddPeriod(tester);

    // The Period number field starts empty, which fails int.tryParse.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid number'), findsOneWidget);
    // The Add Period sub-dialog is still open.
    expect(find.widgetWithText(TextFormField, 'Period number'), findsOneWidget);
  });

  testWidgets('creates a new period, lists it, and closes the add-period dialog', (tester) async {
    final fake = FakePeriodRepository();
    await tester.pumpWidget(wrap(fake));
    await _openManagePeriods(tester);
    await _openAddPeriod(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Period number'), '3');
    await tester.tap(find.widgetWithText(InputDecorator, 'Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InputDecorator, 'End time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The add-period sub-dialog closed - back to the periods list, which now
    // includes the newly-created period as confirmation.
    expect(find.widgetWithText(TextFormField, 'Period number'), findsNothing);
    expect(find.text('Period 3'), findsOneWidget);
    expect(find.text('Manage Periods'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the add-period dialog open on error', (tester) async {
    final fake = FakePeriodRepository(
      failCreateWith: const Failure(code: 'PERIOD_OVERLAP', message: 'This period overlaps an existing one.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _openManagePeriods(tester);
    await _openAddPeriod(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Period number'), '3');
    await tester.tap(find.widgetWithText(InputDecorator, 'Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InputDecorator, 'End time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('This period overlaps an existing one.'), findsOneWidget);
    // The add-period sub-dialog is still open.
    expect(find.widgetWithText(TextFormField, 'Period number'), findsOneWidget);
  });

  testWidgets('editing an existing period updates its row in the list', (tester) async {
    final fake = FakePeriodRepository(periods: [_period]);
    await tester.pumpWidget(wrap(fake));
    await _openManagePeriods(tester);

    expect(find.text('Period 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    // Pre-filled from the existing period, so times don't need re-picking.
    expect(find.widgetWithText(TextFormField, 'Period number'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Period number'), '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Period number'), findsNothing);
    expect(find.text('Period 2'), findsOneWidget);
    expect(find.text('Period 1'), findsNothing);
  });

  group('choosing which bells', () {
    Future<void> openAddPeriod(WidgetTester tester) async {
      await _openManagePeriods(tester);
      await _openAddPeriod(tester);
    }

    testWidgets('a school with no half day is never asked', (tester) async {
      // The test that this cost nobody anything: the form is the one they
      // had before.
      await tester.pumpWidget(wrap(FakePeriodRepository()));
      await openAddPeriod(tester);

      expect(find.byType(SegmentedButton<String>), findsNothing);
    });

    testWidgets('a school with one is asked, and starts on the full day', (tester) async {
      await tester.pumpWidget(wrap(FakePeriodRepository(), week: '1111120'));
      await openAddPeriod(tester);

      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text('The usual bells, for every full day.'), findsOneWidget);
    });

    testWidgets('picking the half day says what that means', (tester) async {
      await tester.pumpWidget(wrap(FakePeriodRepository(), week: '1111120'));
      await openAddPeriod(tester);

      await tester.tap(find.text('Half day'));
      await tester.pumpAndSettle();

      expect(find.text('The shorter bells, for the days marked as half days.'), findsOneWidget);
    });

    testWidgets('the shape reaches the period that gets created', (tester) async {
      final fake = FakePeriodRepository();
      await tester.pumpWidget(wrap(fake, week: '1111120'));
      await openAddPeriod(tester);

      await tester.tap(find.text('Half day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Period number'), '1');
      await tester.tap(find.widgetWithText(InputDecorator, 'Start time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InputDecorator, 'End time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.periods.last.dayShape, WorkingWeek.halfDay);
    });

    testWidgets('a school with no half day still creates full day periods', (tester) async {
      final fake = FakePeriodRepository();
      await tester.pumpWidget(wrap(fake));
      await openAddPeriod(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Period number'), '1');
      await tester.tap(find.widgetWithText(InputDecorator, 'Start time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InputDecorator, 'End time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.periods.last.dayShape, WorkingWeek.fullDay);
    });
  });
}
