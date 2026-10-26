import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/today/data/models/teacher_day.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:edutrack_app/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_check_in_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/session_users.dart';

/// Today in the Teacher app (docs/teacher-app.md, T1): every state the
/// server's answer can put it in.
void main() {
  Widget screen(FakeTodayRepository today, {ThemeData? theme}) {
    return ProviderScope(
      overrides: [
        todayRepositoryProvider.overrideWithValue(today),
        checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, name: 'Asha Rao')),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const Scaffold(body: TodayScreen()),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, FakeTodayRepository today, {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(480, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(screen(today, theme: theme));
    await tester.pumpAndSettle();
  }

  testWidgets("shows the school's date and the periods in order, the current one marked", (tester) async {
    await pump(tester, FakeTodayRepository());

    expect(find.text('Good day, Asha'), findsOneWidget);
    expect(find.text('Monday, October 26, 2026'), findsOneWidget);

    final top = [11, 13, 15].map((id) => tester.getTopLeft(find.byKey(Key('today-period-$id'))).dy).toList();
    expect(top, orderedEquals([...top]..sort()), reason: 'earliest first');

    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('Grade 9 A · Period 3'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('today-period-13')), matching: find.text('Now')), findsOneWidget);
  });

  testWidgets('says what each period owes: filed, owed, or nothing yet', (tester) async {
    await pump(tester, FakeTodayRepository());

    Finder within(int id, String text) =>
        find.descendant(of: find.byKey(Key('today-period-$id')), matching: find.text(text));

    expect(within(11, 'Report owed - tap to file'), findsOneWidget);
    expect(within(13, 'Report filed'), findsOneWidget);
    expect(within(15, 'Report owed - tap to file'), findsNothing, reason: 'a period still to come owes nothing');
    expect(within(15, 'Report filed'), findsNothing);
  });

  testWidgets("shows the class teacher's register and the day's total owed", (tester) async {
    await pump(tester, FakeTodayRepository());

    expect(
      find.descendant(of: find.byKey(const Key('today-register-81')), matching: find.text('Tap to take the register')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('today-register-81')), matching: find.text('Not taken')),
      findsOneWidget,
    );
    expect(find.text('Still to do: 1 register and 1 teaching report.'), findsOneWidget);
  });

  testWidgets('with everything done it says so', (tester) async {
    await pump(
      tester,
      FakeTodayRepository(
        days: [
          teacherDay(
            periods: [samplePeriods[1]],
            registers: const [ClassRegister(classSectionId: 81, classSection: 'Grade 8 A', submitted: true)],
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('today-all-done')), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);
    expect(find.byKey(const Key('today-owed')), findsNothing);
  });

  testWidgets('a teacher who is not a class teacher sees no register card', (tester) async {
    await pump(tester, FakeTodayRepository(days: [teacherDay(registers: const [])]));

    expect(find.textContaining('register'), findsNothing);
    expect(find.text('Still to do: 1 teaching report.'), findsOneWidget);
  });

  testWidgets('a holiday is named and nothing is listed or owed', (tester) async {
    await pump(tester, FakeTodayRepository(days: [teacherDay(isOpen: false, holidayName: 'Diwali')]));

    expect(find.text('Holiday: Diwali'), findsOneWidget);
    expect(find.byKey(const Key('today-owed')), findsNothing);
    expect(find.byKey(const Key('today-period-11')), findsNothing);
  });

  testWidgets('a day the school does not run is closed without a holiday name', (tester) async {
    await pump(tester, FakeTodayRepository(days: [teacherDay(isOpen: false)]));

    expect(find.text('No school today'), findsOneWidget);
  });

  testWidgets('an open day with no periods says so rather than showing a blank', (tester) async {
    await pump(
      tester,
      FakeTodayRepository(
        days: [teacherDay(periods: const [], registers: const [])],
      ),
    );

    expect(find.byKey(const Key('today-no-periods')), findsOneWidget);
    expect(find.byKey(const Key('today-all-done')), findsOneWidget);
  });

  testWidgets('a half day is labelled', (tester) async {
    await pump(tester, FakeTodayRepository(days: [teacherDay(isHalfDay: true)]));

    expect(find.byKey(const Key('today-half-day')), findsOneWidget);
  });

  testWidgets('on leave today, the day is shown but nothing is owed', (tester) async {
    final leave = LeaveSpan(
      id: 7,
      leaveType: 'casual',
      startDate: DateTime(2026, 10, 26),
      endDate: DateTime(2026, 10, 27),
    );

    await pump(
      tester,
      FakeTodayRepository(
        days: [
          teacherDay(leaveToday: leave, leaveThisWeek: [leave]),
        ],
      ),
    );

    expect(find.text('You are on leave today'), findsOneWidget);
    expect(find.textContaining('Casual Leave, 10/26/2026 to 10/27/2026'), findsOneWidget);
    expect(find.byKey(const Key('today-owed')), findsNothing);
    expect(find.byKey(const Key('today-leave-week')), findsNothing, reason: "today's leave is not listed twice");
    expect(find.byKey(const Key('today-period-11')), findsOneWidget);
  });

  testWidgets("later leave this week is listed", (tester) async {
    final later = LeaveSpan(
      id: 8,
      leaveType: 'medical',
      startDate: DateTime(2026, 10, 29),
      endDate: DateTime(2026, 10, 29),
    );

    await pump(
      tester,
      FakeTodayRepository(
        days: [
          teacherDay(leaveThisWeek: [later]),
        ],
      ),
    );

    expect(find.byKey(const Key('today-leave-week')), findsOneWidget);
    expect(find.textContaining('Medical Leave, 10/29/2026'), findsOneWidget);
  });

  testWidgets('a failure shows the error with a retry that asks again', (tester) async {
    final today = FakeTodayRepository(
      failWith: const Failure(
        code: 'NETWORK_ERROR',
        message: 'Could not reach the server. Check your connection and try again.',
      ),
    );
    await pump(tester, today);

    expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);

    today.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-period-11')), findsOneWidget);
    expect(today.calls, 2);
  });

  testWidgets('pulling down asks the server again and shows what has moved on', (tester) async {
    final moved = [
      for (final period in samplePeriods)
        TodayPeriod(
          timetableEntryId: period.timetableEntryId,
          periodNumber: period.periodNumber,
          startTime: period.startTime,
          endTime: period.endTime,
          state: period.periodNumber == 5 ? PeriodState.current : PeriodState.done,
          classSectionId: period.classSectionId,
          classSection: period.classSection,
          subject: period.subject,
          reportFiled: period.reportFiled,
          reportId: period.reportId,
        ),
    ];
    final today = FakeTodayRepository(
      days: [
        teacherDay(),
        teacherDay(periods: moved),
      ],
    );
    await pump(tester, today);

    await tester.fling(find.byKey(const Key('today-list')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(today.calls, 2);
    expect(find.descendant(of: find.byKey(const Key('today-period-15')), matching: find.text('Now')), findsOneWidget);
  });

  testWidgets('reads in dark mode', (tester) async {
    await pump(tester, FakeTodayRepository(), theme: AppTheme.dark());

    expect(find.byKey(const Key('today-period-13')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
