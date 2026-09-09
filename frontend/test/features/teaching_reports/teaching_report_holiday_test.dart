import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
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

Widget wrap(TeachingReportSummary summary) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      timetableRepositoryProvider.overrideWithValue(FakeTimetableRepository()),
      teachingReportRepositoryProvider.overrideWithValue(FakeTeachingReportRepository(summaryData: summary)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: TeachingReportScreen()),
    ),
  );
}

void main() {
  testWidgets('on a holiday the summary shows the holiday and My Teaching Today says so', (tester) async {
    await tester.pumpWidget(
      wrap(const TeachingReportSummary(scheduled: 0, submitted: 0, pending: 0, holiday: 'Independence Day')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Holiday: Independence Day'), findsOneWidget);
    expect(find.text('No periods today - Independence Day is a holiday.'), findsOneWidget);
    expect(find.text('Submit Report'), findsNothing);
  });

  testWidgets('on a normal day no holiday chip is shown', (tester) async {
    await tester.pumpWidget(wrap(const TeachingReportSummary(scheduled: 2, submitted: 1, pending: 1)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Holiday:'), findsNothing);
    expect(find.textContaining('is a holiday.'), findsNothing);
  });
}
