import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report_summary.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/teaching_reports/presentation/teaching_report_screen.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/fake_timetable_repository.dart';

const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

/// Mirrors TeachingReportScreen's own "today" resolution exactly (see
/// _MyScheduleToday._todayDayOfWeek and _today), so this test stays correct
/// regardless of which real-world day it runs on. Weekends have no
/// DayOfWeek match (the enum only has Monday-Friday) - skip those two days
/// since "My Teaching Today" always reads "No periods are scheduled today."
/// on a weekend and there is nothing schedule-specific to assert.
DayOfWeek? _todayAsScheduled() {
  final name = DateFormat('EEEE').format(DateTime.now()).toLowerCase();
  for (final day in DayOfWeek.values) {
    if (day.apiValue == name) return day;
  }
  return null;
}

final _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

Widget wrap({required List<TimetableEntry> entries, required List<TeachingReport> reports}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      timetableRepositoryProvider.overrideWithValue(FakeTimetableRepository(entries: entries)),
      teachingReportRepositoryProvider.overrideWithValue(
        FakeTeachingReportRepository(
          reports: reports,
          summaryData: const TeachingReportSummary(scheduled: 1, submitted: 0, pending: 1),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: TeachingReportScreen()),
    ),
  );
}

void main() {
  final today = _todayAsScheduled();
  if (today == null) {
    // Running on a Saturday/Sunday - no weekday to schedule a period on, so
    // there is nothing to exercise here.
    return;
  }

  final entry = TimetableEntry(
    id: 5,
    schoolId: 1,
    classSectionId: 10,
    classSectionName: 'Grade 8 A',
    periodId: 1,
    periodNumber: 1,
    dayOfWeek: today,
    subjectId: 3,
    subjectName: 'Mathematics',
    teacherId: 20,
    teacherName: 'Priya Sharma',
  );

  testWidgets('an unfiled period shows a Submit Report button', (tester) async {
    await tester.pumpWidget(wrap(entries: [entry], reports: const []));
    await tester.pumpAndSettle();

    expect(find.text('Submit Report'), findsOneWidget);
    expect(find.text('Submitted'), findsNothing);
  });

  testWidgets('a filed but unreviewed period shows a Submitted badge instead of the button', (tester) async {
    final report = TeachingReport(
      id: 1,
      schoolId: 1,
      timetableEntryId: entry.id,
      classSectionName: entry.classSectionName,
      periodNumber: entry.periodNumber,
      subjectName: entry.subjectName,
      teacherId: entry.teacherId,
      teacherName: entry.teacherName,
      reportDate: _today,
      topicTaught: 'Fractions',
      homework: null,
      remarks: null,
      reviewedBy: null,
      reviewedByName: null,
      reviewedAt: null,
    );

    await tester.pumpWidget(wrap(entries: [entry], reports: [report]));
    await tester.pumpAndSettle();

    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Submit Report'), findsNothing);
  });

  testWidgets('a filed and reviewed period shows a Reviewed badge', (tester) async {
    final report = TeachingReport(
      id: 1,
      schoolId: 1,
      timetableEntryId: entry.id,
      classSectionName: entry.classSectionName,
      periodNumber: entry.periodNumber,
      subjectName: entry.subjectName,
      teacherId: entry.teacherId,
      teacherName: entry.teacherName,
      reportDate: _today,
      topicTaught: 'Fractions',
      homework: null,
      remarks: null,
      reviewedBy: 30,
      reviewedByName: 'Rohit Verma',
      reviewedAt: '2026-09-08T10:00:00Z',
    );

    await tester.pumpWidget(wrap(entries: [entry], reports: [report]));
    await tester.pumpAndSettle();

    expect(find.text('Reviewed'), findsOneWidget);
    expect(find.text('Submit Report'), findsNothing);
  });
}
