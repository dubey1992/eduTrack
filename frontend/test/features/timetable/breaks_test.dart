import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/application/school_week_provider.dart';
import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:edutrack_app/features/timetable/application/break_planner.dart';
import 'package:edutrack_app/features/timetable/data/break_repository.dart';
import 'package:edutrack_app/features/timetable/data/models/period.dart';
import 'package:edutrack_app/features/timetable/data/models/school_break.dart';
import 'package:edutrack_app/features/timetable/data/period_repository.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/edit_break_dialog.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/manage_periods_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_break_repository.dart';
import '../../support/fake_period_repository.dart';

/// Breaks in the school day: where one probably goes, what a time runs into,
/// and the form that makes setting one up quick.

Period _p(int number, String start, String end) =>
    Period(id: number, schoolId: 1, periodNumber: number, startTime: start, endTime: end);

/// Five periods back to back, 08:00 to 11:45.
final packed = [
  _p(1, '08:00', '08:45'),
  _p(2, '08:45', '09:30'),
  _p(3, '09:30', '10:15'),
  _p(4, '10:15', '11:00'),
  _p(5, '11:00', '11:45'),
];

void main() {
  group('the planner', () {
    test('a short break goes after the second period when the day is packed', () {
      final suggested = suggest(slotsOf(packed, const []), 15, lunch: false);

      expect((suggested!.start, suggested.end), ('09:30', '09:45'));
    });

    test('lunch goes after the period ending nearest the middle of the day', () {
      // 08:00 to 11:45: the middle is 09:52, and Period 2 ends nearest it, at 09:30.
      final suggested = suggest(slotsOf(packed, const []), 30, lunch: true);

      expect((suggested!.start, suggested.end), ('09:30', '10:00'));
    });

    test('a free gap long enough is used first', () {
      final gapped = [_p(1, '08:00', '08:45'), _p(2, '08:45', '09:30'), _p(3, '10:00', '10:45')];

      final suggested = suggest(slotsOf(gapped, const []), 30, lunch: true);

      expect((suggested!.start, suggested.end), ('09:30', '10:00'));
    });

    test('no periods, no suggestion', () {
      expect(suggest(const [], 30, lunch: true), isNull);
    });

    test('a break starting mid-period is caught, and says when that period ends', () {
      final found = clashes(slotsOf(packed, const []), '10:30', '11:00');

      expect(found.startsDuring?.label, 'Period 4');
      expect(clockOf(found.startsDuring!.end), '11:00');
    });

    test('a break over the next periods says how much room is needed', () {
      final found = clashes(slotsOf(packed, const []), '10:15', '10:45');

      expect(found.overlaps?.label, 'Period 4');
      expect(found.roomNeeded, 30);
    });

    test('a break in a free gap clashes with nothing', () {
      final found = clashes(slotsOf(packed, const []), '11:45', '12:25');

      expect((found.startsDuring, found.overlaps, found.roomNeeded), (null, null, 0));
    });

    test('an existing break counts as part of the day, but never itself', () {
      const lunch = SchoolBreak(id: 7, schoolId: 1, name: 'Lunch break', startTime: '11:45', endTime: '12:25');

      expect(clashes(slotsOf(packed, const [lunch]), '12:00', '12:30').startsDuring?.label, 'the Lunch break');
      expect(clashes(slotsOf(packed, const [lunch], ignoringBreak: 7), '12:00', '12:30').startsDuring, isNull);
    });
  });

  group('the Add Break form', () {
    Widget wrap(FakeBreakRepository breaks, {List<Period>? periods, String week = '1111100'}) {
      return ProviderScope(
        overrides: [
          breakRepositoryProvider.overrideWithValue(breaks),
          periodRepositoryProvider.overrideWithValue(FakePeriodRepository(periods: periods ?? packed)),
          schoolWeekProvider(null).overrideWithValue(WorkingWeek.fromApiValue(week)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showDialog(context: context, builder: (_) => const ManagePeriodsDialog(schoolId: null)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openAddBreak(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-break')));
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, Key key) =>
        (tester
                    .widget<InputDecorator>(find.descendant(of: find.byKey(key), matching: find.byType(InputDecorator)))
                    .child
                as Text)
            .data!;

    testWidgets('a preset fills the name and suggests the time from the periods', (tester) async {
      await tester.pumpWidget(wrap(FakeBreakRepository()));
      await openAddBreak(tester);

      await tester.tap(find.byKey(const Key('break-preset-1')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Lunch break'), findsOneWidget);
      expect(text(tester, const Key('break-start')), '09:30');
      expect(text(tester, const Key('break-end')), '10:00');
    });

    testWidgets('a packed day ticks "move later periods" for you, and saving sends it', (tester) async {
      final breaks = FakeBreakRepository();
      await tester.pumpWidget(wrap(breaks));
      await openAddBreak(tester);

      await tester.tap(find.byKey(const Key('break-preset-1')));
      await tester.pumpAndSettle();

      expect(find.text('Move later periods back by 30 min'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('break-make-room'))).value, isTrue);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(breaks.calls.single, {
        'op': 'create',
        'name': 'Lunch break',
        'day_shape': 'full',
        'start': '09:30',
        'end': '10:00',
        'make_room': true,
      });
      expect(find.text('Lunch break added.'), findsOneWidget);
      expect(find.byType(EditBreakDialog), findsNothing);
    });

    testWidgets('a break in a free gap says it fits and moves nothing', (tester) async {
      final breaks = FakeBreakRepository();
      final gapped = [_p(1, '08:00', '08:45'), _p(2, '08:45', '09:30'), _p(3, '10:00', '10:45')];
      await tester.pumpWidget(wrap(breaks, periods: gapped));
      await openAddBreak(tester);

      await tester.tap(find.byKey(const Key('break-preset-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('break-fits')), findsOneWidget);
      expect(find.byKey(const Key('break-make-room')), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(breaks.calls.single['make_room'], isFalse);
    });

    testWidgets('no name is refused before anything is sent', (tester) async {
      final breaks = FakeBreakRepository();
      await tester.pumpWidget(wrap(breaks));
      await openAddBreak(tester);

      await tester.tap(find.byKey(const Key('break-preset-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('break-name')), '  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Give the break a name'), findsOneWidget);
      expect(breaks.calls, isEmpty);
    });

    testWidgets("the server's refusal is shown in the form", (tester) async {
      final breaks = FakeBreakRepository(
        failCreateWith: const Failure(code: 'VALIDATION', message: 'It overlaps Period 4 (10:15-11:00).'),
      );
      await tester.pumpWidget(wrap(breaks));
      await openAddBreak(tester);

      await tester.tap(find.byKey(const Key('break-preset-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('It overlaps Period 4 (10:15-11:00).'), findsOneWidget);
      expect(find.byType(EditBreakDialog), findsOneWidget);
    });

    testWidgets('a school with half days chooses which day a break belongs to', (tester) async {
      await tester.pumpWidget(wrap(FakeBreakRepository(), week: '1111120'));
      await openAddBreak(tester);

      expect(find.text('Half day'), findsOneWidget);
    });

    testWidgets('breaks are listed in the dialog and can be removed', (tester) async {
      final breaks = FakeBreakRepository(
        breaks: [const SchoolBreak(id: 3, schoolId: 1, name: 'Lunch break', startTime: '11:45', endTime: '12:25')],
      );
      await tester.pumpWidget(wrap(breaks));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Lunch break'), findsOneWidget);
      expect(find.text('11:45 - 12:25'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(breaks.breaks, isEmpty);
      expect(find.text('Lunch break'), findsNothing);
    });
  });
}
