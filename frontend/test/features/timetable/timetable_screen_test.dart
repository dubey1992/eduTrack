import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/schools/data/models/working_week.dart';
import 'package:edutrack_app/features/timetable/data/models/period.dart';
import 'package:edutrack_app/features/timetable/data/models/school_break.dart';
import 'package:edutrack_app/features/timetable/data/period_repository.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:edutrack_app/features/timetable/presentation/timetable_screen.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/edit_entry_dialog.dart';
import 'package:edutrack_app/features/timetable/presentation/widgets/manage_periods_dialog.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:edutrack_app/features/timetable/data/break_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_break_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_period_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_subject_repository.dart';
import '../../support/fake_timetable_repository.dart';
import '../../support/fake_user_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

final _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 5, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: 9, classTeacherName: 'Admin'),
  ],
);

const _period = Period(id: 1, schoolId: 1, periodNumber: 1, startTime: '08:30', endTime: '09:15');
const _halfPeriod = Period(
  id: 2,
  schoolId: 1,
  periodNumber: 1,
  dayShape: WorkingWeek.halfDay,
  startTime: '09:00',
  endTime: '09:40',
);

Widget wrap(
  AuthenticatedUser actor, {
  FakeSchoolClassRepository? schoolClasses,
  FakePeriodRepository? periods,
  FakeTimetableRepository? timetable,
  FakeBreakRepository? breaks,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      schoolClassRepositoryProvider.overrideWithValue(schoolClasses ?? FakeSchoolClassRepository()),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      subjectRepositoryProvider.overrideWithValue(FakeSubjectRepository()),
      breakRepositoryProvider.overrideWithValue(breaks ?? FakeBreakRepository()),
      periodRepositoryProvider.overrideWithValue(periods ?? FakePeriodRepository()),
      timetableRepositoryProvider.overrideWithValue(timetable ?? FakeTimetableRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: TimetableScreen()),
    ),
  );
}

void main() {
  group('breaks in the grid', () {
    const p1 = Period(id: 11, schoolId: 1, periodNumber: 1, startTime: '08:00', endTime: '08:45');
    const p2 = Period(id: 12, schoolId: 1, periodNumber: 2, startTime: '08:45', endTime: '09:30');
    const p3 = Period(id: 13, schoolId: 1, periodNumber: 3, startTime: '09:45', endTime: '10:30');

    testWidgets('a break sits between the periods it falls between, on every day', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrap(
          _schoolAdmin,
          schoolClasses: FakeSchoolClassRepository(classes: [_schoolClass]),
          periods: FakePeriodRepository(periods: [p3, p1, p2]),
          timetable: FakeTimetableRepository(),
          breaks: FakeBreakRepository(
            breaks: [const SchoolBreak(id: 1, schoolId: 1, name: 'Short break', startTime: '09:30', endTime: '09:45')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      final p2Row = tester.getTopLeft(find.text('P2\n08:45')).dy;
      final breakRow = tester.getTopLeft(find.text('09:30\n09:45')).dy;
      final p3Row = tester.getTopLeft(find.text('P3\n09:45')).dy;
      expect(p2Row < breakRow && breakRow < p3Row, isTrue);
      // Named under every day's column, and nothing to tap there.
      expect(find.text('Short break'), findsNWidgets(5));
    });

    testWidgets('a half day break stays off the full day grid', (tester) async {
      await tester.pumpWidget(
        wrap(
          _schoolAdmin,
          schoolClasses: FakeSchoolClassRepository(classes: [_schoolClass]),
          periods: FakePeriodRepository(periods: [p1, p2]),
          timetable: FakeTimetableRepository(),
          breaks: FakeBreakRepository(
            breaks: [
              const SchoolBreak(
                id: 2,
                schoolId: 1,
                name: 'Snack',
                dayShape: WorkingWeek.halfDay,
                startTime: '08:45',
                endTime: '09:00',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.text('Snack'), findsNothing);
    });
  });

  testWidgets('a school admin sees the admin controls (class picker, manage periods)', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Class schedules and period management.'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Class'), findsOneWidget);
    expect(find.text('Periods & Breaks'), findsOneWidget);
    expect(find.text('Pick a class section to view its timetable.'), findsOneWidget);
  });

  testWidgets('a teacher sees their own read-only schedule with no admin controls', (tester) async {
    await tester.pumpWidget(wrap(_teacher));
    await tester.pumpAndSettle();

    expect(find.text('Your weekly teaching schedule.'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Class'), findsNothing);
    expect(find.text('Periods & Breaks'), findsNothing);
    expect(find.text('No periods assigned to you yet.'), findsOneWidget);
  });

  testWidgets('tapping an empty grid cell opens EditEntryDialog in create mode', (tester) async {
    await tester.pumpWidget(
      wrap(
        _schoolAdmin,
        schoolClasses: FakeSchoolClassRepository(classes: [_schoolClass]),
        periods: FakePeriodRepository(periods: [_period]),
        timetable: FakeTimetableRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();

    // Every cell in the (empty) grid is unassigned, so shows an add icon.
    expect(find.byIcon(Icons.add), findsWidgets);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.byType(EditEntryDialog), findsOneWidget);
    // No entry behind this cell, so it's create mode - no Clear button.
    expect(find.widgetWithText(TextButton, 'Clear'), findsNothing);
  });

  testWidgets('tapping Manage Periods opens ManagePeriodsDialog', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Periods & Breaks'));
    await tester.pumpAndSettle();

    expect(find.byType(ManagePeriodsDialog), findsOneWidget);
    expect(find.widgetWithText(AlertDialog, 'Periods & Breaks'), findsOneWidget);
  });

  group('the columns follow the week the school keeps', () {
    // docs/holidays.md: a grid that assumed Monday to Friday would offer a
    // teacher in the Gulf a column the server refuses to write to, and hide
    // the Sunday they actually teach on.
    testWidgets('a Monday to Friday school gets five weekday columns', (tester) async {
      await tester.pumpWidget(gridFor(_schoolAdmin));
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Friday'), findsOneWidget);
      expect(find.text('Saturday'), findsNothing);
      expect(find.text('Sunday'), findsNothing);
    });

    testWidgets('a Sunday to Thursday school gets Sunday and not Friday', (tester) async {
      await tester.pumpWidget(
        gridFor(
          AuthenticatedUser(
            id: 9,
            name: 'Admin',
            email: 'admin@example.com',
            role: UserRole.schoolAdmin,
            workingDays: WorkingWeek.fromApiValue('1111001'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.text('Sunday'), findsOneWidget);
      expect(find.text('Friday'), findsNothing);
      expect(find.text('Saturday'), findsNothing);
    });

    testWidgets('a six day school gets Saturday', (tester) async {
      await tester.pumpWidget(
        gridFor(
          AuthenticatedUser(
            id: 9,
            name: 'Admin',
            email: 'admin@example.com',
            role: UserRole.schoolAdmin,
            workingDays: WorkingWeek.fromApiValue('1111110'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.text('Saturday'), findsOneWidget);
      expect(find.text('Sunday'), findsNothing);
    });
  });

  group('a full day and a half day are two grids', () {
    Widget gridWeek(String week, {List<Period> periods = const [_period]}) {
      return wrap(
        AuthenticatedUser(
          id: 9,
          name: 'Admin',
          email: 'admin@example.com',
          role: UserRole.schoolAdmin,
          workingDays: WorkingWeek.fromApiValue(week),
        ),
        schoolClasses: FakeSchoolClassRepository(classes: [_schoolClass]),
        periods: FakePeriodRepository(periods: periods),
        timetable: FakeTimetableRepository(),
      );
    }

    testWidgets('a school with no half day gets one grid and no headings', (tester) async {
      // The screen it had before any of this.
      await tester.pumpWidget(gridWeek('1111100'));
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.textContaining('Full days'), findsNothing);
      expect(find.textContaining('Half days'), findsNothing);
      expect(find.text('Monday'), findsOneWidget);
    });

    testWidgets('a school with one gets both, each naming its days', (tester) async {
      await tester.pumpWidget(gridWeek('1111120', periods: [_period, _halfPeriod]));
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.text('Full days · Monday, Tuesday, Wednesday, Thursday, Friday'), findsOneWidget);
      expect(find.text('Half days · Saturday'), findsOneWidget);
      // Saturday is a column of the half grid, not of the full one.
      expect(find.text('Saturday'), findsOneWidget);
    });

    testWidgets('a half day with no periods says so rather than drawing nothing', (tester) async {
      await tester.pumpWidget(gridWeek('1111120'));
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.text('No periods for half days yet. Add them in Manage Periods.'), findsOneWidget);
      // And the full grid is still there.
      expect(find.text('Monday'), findsOneWidget);
    });

    testWidgets('periods left over from a half day nobody keeps are named, not dropped', (tester) async {
      // Somebody built those bells and then unmarked the day. A grid that
      // simply does not show them looks like they were lost.
      await tester.pumpWidget(gridWeek('1111100', periods: [_period, _halfPeriod]));
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.text('1 period is set up for half days, but no day is marked as one.'), findsOneWidget);
    });

    testWidgets('a school with no half day and no stray periods says nothing', (tester) async {
      await tester.pumpWidget(gridWeek('1111100'));
      await tester.pumpAndSettle();
      await pickTheSection(tester);

      expect(find.textContaining('set up for half days'), findsNothing);
    });
  });
}

/// The screen with enough behind it to draw a grid, for the column tests.
Widget gridFor(AuthenticatedUser actor) {
  return wrap(
    actor,
    schoolClasses: FakeSchoolClassRepository(classes: [_schoolClass]),
    periods: FakePeriodRepository(periods: [_period]),
    timetable: FakeTimetableRepository(),
  );
}

Future<void> pickTheSection(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Grade 8 A').last);
  await tester.pumpAndSettle();
}
