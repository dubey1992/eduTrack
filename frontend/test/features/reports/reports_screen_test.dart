import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/reports/data/models/report.dart';
import 'package:edutrack_app/features/reports/data/report_repository.dart';
import 'package:edutrack_app/features/reports/presentation/reports_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_report_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeReportRepository fake, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      reportRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: ReportsScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Phase 18's reports screen.
///
/// The figures come from the API; what these check is that the screen shows
/// them honestly - the working-day denominator, a missing rate as a dash, and
/// only the reports a role is actually allowed to open.
void main() {
  testWidgets('shows the rows and the working-day denominator behind them', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeReportRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Arjun Kumar'), findsOneWidget);
    expect(find.text('Meera Singh'), findsOneWidget);
    // Stated, because it is what every percentage on the screen is out of.
    expect(find.text('Working days'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('60.0%'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
  });

  testWidgets('shows a period the school never opened as having nothing to measure', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeReportRepository(result: closedWeekResult)));
    await tester.pumpAndSettle();

    expect(find.textContaining('did not run on any day'), findsOneWidget);
    // And certainly not 0%, which would read as everybody absent.
    expect(find.text('0.0%'), findsNothing);
  });

  testWidgets('says so when there is nothing to report', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeReportRepository(result: emptyResult)));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to report for this period.'), findsOneWidget);
  });

  testWidgets('switching report asks the API for that report', (tester) async {
    useDesktop(tester);
    final fake = FakeReportRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(fake.lastKind, ReportKind.studentAttendance);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transport usage'));
    await tester.pumpAndSettle();

    expect(fake.lastKind, ReportKind.transportUsage);
  });

  testWidgets('offers a head of department only the reports they may open', (tester) async {
    useDesktop(tester);
    const hod = AuthenticatedUser(id: 5, name: 'Rahul', email: 'r@example.com', role: UserRole.hod);
    await tester.pumpWidget(wrap(FakeReportRepository(), actor: hod));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Staff attendance & leave'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Teaching & syllabus'), findsOneWidget);
    // A head of department has no school-wide student report - offering the
    // tab would only produce a 403.
    expect(find.widgetWithText(ChoiceChip, 'Student attendance'), findsNothing);
  });

  testWidgets('offers a transport manager only transport', (tester) async {
    useDesktop(tester);
    const manager = AuthenticatedUser(id: 6, name: 'Karan', email: 'k@example.com', role: UserRole.transportManager);
    await tester.pumpWidget(wrap(FakeReportRepository(), actor: manager));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Transport usage'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Staff attendance & leave'), findsNothing);
  });

  testWidgets('offers an accountant staff attendance only - the register payroll is computed from', (tester) async {
    useDesktop(tester);
    const accountant = AuthenticatedUser(id: 7, name: 'Meena', email: 'm@example.com', role: UserRole.accountant);
    await tester.pumpWidget(wrap(FakeReportRepository(), actor: accountant));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Staff attendance & leave'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Student attendance'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Transport usage'), findsNothing);
  });

  testWidgets('tells a role with no reports plainly', (tester) async {
    useDesktop(tester);
    const teacher = AuthenticatedUser(id: 9, name: 'Priya', email: 'p@example.com', role: UserRole.teacher);
    await tester.pumpWidget(wrap(FakeReportRepository(), actor: teacher));
    await tester.pumpAndSettle();

    expect(find.text('Reports are not available for your role.'), findsOneWidget);
  });

  testWidgets('exporting asks for the CSV of the report on screen', (tester) async {
    useDesktop(tester);
    final fake = FakeReportRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Teaching & syllabus'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export CSV'));
    await tester.pumpAndSettle();

    expect(fake.downloadCalls, 1);
    expect(fake.lastKind, ReportKind.teachingCoverage);
  });

  testWidgets('an export that cannot be saved says why rather than failing quietly', (tester) async {
    // Off the web there is no download mechanism wired up yet; the message
    // has to reach the user instead of the button appearing to work.
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeReportRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export CSV'));
    await tester.pumpAndSettle();

    expect(find.textContaining('only available in the web app'), findsOneWidget);
  });

  testWidgets('shows an error with a retry when a report fails', (tester) async {
    useDesktop(tester);
    final fake = FakeReportRepository(
      failWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });

  group('a whole group', () {
    testWidgets('breaks the figures down by branch', (tester) async {
      await tester.pumpWidget(wrap(FakeReportRepository(result: groupResult)));
      await tester.pumpAndSettle();

      expect(find.text('By branch'), findsOneWidget);
      expect(find.text("St Mary's North"), findsWidgets);
      expect(find.text("St Mary's South"), findsWidgets);
    });

    testWidgets('shows each branch its own working days', (tester) async {
      // The whole reason the report runs once per branch: a holiday at one
      // is not a holiday at the other.
      await tester.pumpWidget(wrap(FakeReportRepository(result: groupResult)));
      await tester.pumpAndSettle();

      expect(find.text('5'), findsWidgets);
      expect(find.text('4'), findsWidgets);
    });

    testWidgets('does not claim the group has working days of its own', (tester) async {
      await tester.pumpWidget(wrap(FakeReportRepository(result: groupResult)));
      await tester.pumpAndSettle();

      // Adding two schools' calendars together would be a number that means
      // nothing, so the header simply does not offer one.
      expect(find.text('Working days'), findsOneWidget, reason: 'only the by-branch column, not a header fact');
    });

    testWidgets('names the branch on every row of the table', (tester) async {
      await tester.pumpWidget(wrap(FakeReportRepository(result: groupResult)));
      await tester.pumpAndSettle();

      expect(find.text('School'), findsWidgets);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Ishaan Patel'), findsOneWidget);
    });

    testWidgets('a single school report has no breakdown and no School column', (tester) async {
      await tester.pumpWidget(wrap(FakeReportRepository()));
      await tester.pumpAndSettle();

      expect(find.text('By branch'), findsNothing);
      expect(find.text('School'), findsNothing);
    });
  });
}
