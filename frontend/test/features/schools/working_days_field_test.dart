import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:edutrack_app/features/schools/presentation/widgets/working_days_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picking the days a school runs (docs/holidays.md).
///
/// It decides more than it looks like it decides: attendance is refused on a
/// day the school does not run, no period is taught, no bus goes, and every
/// rate in every report is out of the days that are left.
Finder chipIn(String row, String label) =>
    find.descendant(of: find.byKey(Key(row)), matching: find.widgetWithText(FilterChip, label));

void main() {
  late WorkingWeek current;

  Widget wrap(WorkingWeek value) {
    current = value;

    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) =>
              WorkingDaysField(value: current, onChanged: (week) => setState(() => current = week)),
        ),
      ),
    );
  }

  testWidgets('it shows a chip for every day of the week', (tester) async {
    await tester.pumpWidget(wrap(const WorkingWeek.mondayToFriday()));

    for (final label in WorkingWeek.shortLabels) {
      expect(chipIn('working-days', label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the days the school runs are the ones selected', (tester) async {
    await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1111001')));

    FilterChip chipFor(String label) => tester.widget<FilterChip>(chipIn('working-days', label));

    expect(chipFor('Su').selected, isTrue);
    expect(chipFor('Fr').selected, isFalse);
  });

  testWidgets('tapping a day turns it on, and the summary follows', (tester) async {
    await tester.pumpWidget(wrap(const WorkingWeek.mondayToFriday()));

    expect(find.textContaining('Monday to Friday'), findsOneWidget);

    await tester.tap(chipIn('working-days', 'Sa'));
    await tester.pumpAndSettle();

    expect(current.apiValue, '1111110');
    expect(find.textContaining('Monday to Saturday'), findsOneWidget);
  });

  testWidgets('a week that wraps past Sunday is named the way people name it', (tester) async {
    await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1111001')));

    expect(find.textContaining('Sunday to Thursday'), findsOneWidget);
  });

  testWidgets('it says what the days actually control', (tester) async {
    await tester.pumpWidget(wrap(const WorkingWeek.mondayToFriday()));

    // Seven unexplained chips would be a setting somebody changes without
    // knowing it moves every report they have.
    expect(find.textContaining('Attendance, periods, buses'), findsOneWidget);
  });

  testWidgets('a week with no days in it asks for one', (tester) async {
    await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1000000')));

    await tester.tap(chipIn('working-days', 'Mo'));
    await tester.pumpAndSettle();

    expect(current.isEmpty, isTrue);
    expect(find.text('Pick at least one day.'), findsOneWidget);
    // And nothing claiming the school runs on no days in particular.
    expect(find.textContaining('Attendance, periods, buses'), findsNothing);
  });

  testWidgets('a half day is marked on the chip, not only underneath', (tester) async {
    // It looks exactly like a full day otherwise, and turning one off and on
    // again quietly makes it full.
    await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1111120')));

    expect(chipIn('working-days', 'Sa ½'), findsOneWidget);
    expect(chipIn('working-days', 'Mo'), findsOneWidget);
    expect(find.text('Saturday is a half day.'), findsOneWidget);
  });

  testWidgets('a week with no half days says nothing about them', (tester) async {
    await tester.pumpWidget(wrap(const WorkingWeek.mondayToFriday()));

    expect(find.textContaining('half day'), findsNothing);
    expect(chipIn('working-days', 'Sa'), findsOneWidget);
  });

  testWidgets('turning a half day off and on again shows it became full', (tester) async {
    await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1111120')));

    await tester.tap(chipIn('working-days', 'Sa ½'));
    await tester.pumpAndSettle();
    await tester.tap(chipIn('working-days', 'Sa'));
    await tester.pumpAndSettle();

    expect(current.apiValue, '1111110');
    expect(find.textContaining('half day'), findsNothing);
  });

  group('the half days row', () {
    testWidgets('it offers only the days the school actually runs', (tester) async {
      // A day cannot be short and closed at once - the model cannot hold
      // that, and neither can the screen.
      await tester.pumpWidget(wrap(const WorkingWeek.mondayToFriday()));

      expect(chipIn('half-days', 'Mo'), findsOneWidget);
      expect(chipIn('half-days', 'Sa'), findsNothing);
      expect(chipIn('half-days', 'Su'), findsNothing);
    });

    testWidgets('marking a day short does not turn it off', (tester) async {
      await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1111110')));

      await tester.tap(chipIn('half-days', 'Sa'));
      await tester.pumpAndSettle();

      expect(current.apiValue, '1111120');
      expect(current.runsOn(5), isTrue);
      expect(current.length, 6);
      expect(find.text('Saturday is a half day.'), findsOneWidget);
    });

    testWidgets('unmarking it leaves a full day behind, not a closed one', (tester) async {
      await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1111120')));

      await tester.tap(chipIn('half-days', 'Sa'));
      await tester.pumpAndSettle();

      expect(current.apiValue, '1111110');
      expect(current.runsOn(5), isTrue);
    });

    testWidgets('turning a day off takes it out of the half days row', (tester) async {
      await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1111120')));

      await tester.tap(chipIn('working-days', 'Sa ½'));
      await tester.pumpAndSettle();

      expect(current.apiValue, '1111100');
      expect(chipIn('half-days', 'Sa'), findsNothing);
    });

    testWidgets('a week with no days has nothing to mark short', (tester) async {
      await tester.pumpWidget(wrap(WorkingWeek.fromApiValue('1000000')));

      await tester.tap(chipIn('working-days', 'Mo'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('half-days')), findsNothing);
    });

    testWidgets('it says a half day is still a full working day', (tester) async {
      // The decision everything else rests on, where somebody setting it
      // will read it.
      await tester.pumpWidget(wrap(const WorkingWeek.mondayToFriday()));

      expect(find.textContaining('count as full working days'), findsOneWidget);
    });
  });
}
