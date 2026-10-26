import 'package:edutrack_app/features/auth/application/school_clock_provider.dart';
import 'package:edutrack_app/core/utils/date_period.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report_summary.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/teaching_reports/presentation/teaching_report_screen.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/fake_timetable_repository.dart';

const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);
const _hod = AuthenticatedUser(id: 30, name: 'Rohit Verma', email: 'rohit@example.com', role: UserRole.hod);
const _schoolAdmin = AuthenticatedUser(id: 9, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _staff = AuthenticatedUser(id: 40, name: 'Anita', email: 'anita@example.com', role: UserRole.staff);

Widget wrap(AuthenticatedUser actor, {List<TeachingReport> reports = const [], FakeTeachingReportRepository? fake}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      timetableRepositoryProvider.overrideWithValue(FakeTimetableRepository()),
      teachingReportRepositoryProvider.overrideWithValue(
        fake ??
            FakeTeachingReportRepository(
              reports: reports,
              summaryData: const TeachingReportSummary(scheduled: 3, submitted: 1, pending: 2),
            ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: TeachingReportScreen()),
    ),
  );
}

const _ownReport = TeachingReport(
  id: 1,
  schoolId: 1,
  timetableEntryId: 5,
  classSectionName: 'Grade 8 A',
  periodNumber: 1,
  subjectName: 'Mathematics',
  teacherId: 9,
  teacherName: 'Admin',
  reportDate: '2026-09-08',
  topicTaught: 'Fractions',
  homework: null,
  remarks: null,
  reviewedBy: null,
  reviewedByName: null,
  reviewedAt: null,
);

const _othersReport = TeachingReport(
  id: 2,
  schoolId: 1,
  timetableEntryId: 6,
  classSectionName: 'Grade 8 B',
  periodNumber: 2,
  subjectName: 'Science',
  teacherId: 20,
  teacherName: 'Priya Sharma',
  reportDate: '2026-09-08',
  topicTaught: 'Photosynthesis',
  homework: null,
  remarks: null,
  reviewedBy: null,
  reviewedByName: null,
  reviewedAt: null,
);

/// The range a period stands for on the school clock the screen reads.
(String?, String?) rangeOn(WidgetTester tester, Type screen, DatePeriod period) {
  final today = ProviderScope.containerOf(tester.element(find.byType(screen))).read(schoolClockProvider).today;
  final range = period.rangeFrom(today);

  return (range?.from, range?.to);
}

void main() {
  testWidgets('a teacher sees "My Teaching Today" but not the review feed', (tester) async {
    await tester.pumpWidget(wrap(_teacher));
    await tester.pumpAndSettle();

    expect(find.text('My Teaching Today'), findsOneWidget);
    expect(find.text('Reports to Review'), findsNothing);
    expect(find.text('Scheduled Today'), findsOneWidget);
  });

  testWidgets('a school admin sees the review feed but not "My Teaching Today"', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Reports to Review'), findsOneWidget);
    expect(find.text('My Teaching Today'), findsNothing);
    expect(find.text('No teaching reports yet.'), findsOneWidget);
  });

  testWidgets('an hod sees both sections - they teach and they review', (tester) async {
    await tester.pumpWidget(wrap(_hod));
    await tester.pumpAndSettle();

    expect(find.text('My Teaching Today'), findsOneWidget);
    expect(find.text('Reports to Review'), findsOneWidget);
  });

  testWidgets('a staff role sees neither section, only the KPI summary', (tester) async {
    await tester.pumpWidget(wrap(_staff));
    await tester.pumpAndSettle();

    expect(find.text('My Teaching Today'), findsNothing);
    expect(find.text('Reports to Review'), findsNothing);
    expect(find.text('Scheduled Today'), findsOneWidget);
  });

  testWidgets('a reviewer cannot mark reviewed their own report in the review feed', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin, reports: [_ownReport]));
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Mark Reviewed'), findsNothing);
  });

  testWidgets('a reviewer can mark someone elses report reviewed, and the badge updates', (tester) async {
    await tester.pumpWidget(wrap(_schoolAdmin, reports: [_othersReport]));
    await tester.pumpAndSettle();

    expect(find.text('Mark Reviewed'), findsOneWidget);
    expect(find.text('Pending Review'), findsOneWidget);

    await tester.tap(find.text('Mark Reviewed'));
    await tester.pumpAndSettle();

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Reviewed'), findsOneWidget);
    expect(find.text('Report reviewed.'), findsOneWidget);
  });

  group('Reports to Review by period', () {
    testWidgets('starts on All - no range is sent', (tester) async {
      final fake = FakeTeachingReportRepository(reports: [_othersReport]);
      await tester.pumpWidget(wrap(_schoolAdmin, fake: fake));
      await tester.pumpAndSettle();

      expect(fake.lastListRange, (null, null));
      expect(find.text('Photosynthesis'), findsWidgets);
    });

    testWidgets('This week asks the server for Monday to Sunday of the school week', (tester) async {
      final fake = FakeTeachingReportRepository(reports: [_othersReport]);
      await tester.pumpWidget(wrap(_schoolAdmin, fake: fake));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('period-week')));
      await tester.tap(find.byKey(const Key('period-week')));
      await tester.pumpAndSettle();

      expect(fake.lastListRange, rangeOn(tester, TeachingReportScreen, DatePeriod.week));
    });

    testWidgets('an empty period says which period it is about', (tester) async {
      final fake = FakeTeachingReportRepository();
      await tester.pumpWidget(wrap(_schoolAdmin, fake: fake));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('period-month')));
      await tester.tap(find.byKey(const Key('period-month')));
      await tester.pumpAndSettle();

      expect(fake.lastListRange, rangeOn(tester, TeachingReportScreen, DatePeriod.month));
      expect(find.text('No teaching reports this month.'), findsOneWidget);
    });

    testWidgets('a teacher has no review feed, so no period chips either', (tester) async {
      await tester.pumpWidget(wrap(_teacher));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('period-filter')), findsNothing);
    });
  });
}
