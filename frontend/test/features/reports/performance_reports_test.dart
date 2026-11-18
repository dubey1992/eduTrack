import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/reports/application/report_link.dart';
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

/// The performance reports and the period picker (fixed 2026-11-18).

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

Widget _wrap(FakeReportRepository fake, {ReportLink link = const ReportLink()}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      reportRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ReportsScreen(link: link)),
    ),
  );
}

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _student({
  required int id,
  String grading = 'percentage',
  Object? average = 72.5,
  String? grade = 'B',
  Object? gpa,
}) => {
  'student_id': id,
  'admission_number': 'ADM-$id',
  'student': 'Student $id',
  'class_section': 'Class 2 A',
  'subjects': 2,
  'assessments': 4,
  'absent': 0,
  'average_percentage': average,
  'grade': grade,
  'gpa': gpa,
  'class_average_percentage': average,
  'weak_subjects': 0,
  'attendance_rate': 90.0,
  'grading': grading,
};

ReportResult _students(List<Map<String, dynamic>> rows, {Map<String, dynamic>? totals}) => ReportResult.fromJson({
  'range': {'from': '2026-04-01', 'to': '2026-11-18', 'working_days': 150},
  'rows': rows,
  'totals': totals ?? {'students': rows.length, 'tests_held': 4, 'average_percentage': 70.3},
});

/// The picker's visible card - its Dialog's Material - rather than the
/// dialog widget itself, which always fills the route.
Finder _card() => find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first;

void main() {
  group('the period picker', () {
    testWidgets('opens as a popup on a laptop, not across the whole page', (tester) async {
      _screen(tester, const Size(1400, 1000));
      await tester.pumpWidget(_wrap(FakeReportRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('report-period')));
      await tester.pumpAndSettle();

      final picker = tester.getSize(_card());
      expect(picker.width, lessThanOrEqualTo(420));
      expect(picker.height, lessThanOrEqualTo(600));
    });

    testWidgets('keeps the full screen on a phone', (tester) async {
      // Below the 600 px line; wide enough for the stock picker's header in
      // the test font, which draws every letter as a full square.
      _screen(tester, const Size(560, 900));
      await tester.pumpWidget(_wrap(FakeReportRepository()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('report-period')));
      await tester.tap(find.byKey(const Key('report-period')));
      await tester.pumpAndSettle();

      expect(tester.getSize(_card()).width, 560);
    });
  });

  group('the performance reports', () {
    testWidgets('open on the current term, not this month', (tester) async {
      _screen(tester, const Size(1400, 1000));
      final fake = FakeReportRepository(
        resultsByKind: {
          ReportKind.studentPerformance: _students([_student(id: 1)]),
        },
      );
      await tester.pumpWidget(_wrap(fake, link: const ReportLink(kind: ReportKind.studentPerformance)));
      await tester.pumpAndSettle();

      expect(find.text('Current term'), findsOneWidget);
      // No period sent: the server picks the term so far.
      expect((fake.lastFrom, fake.lastTo), (null, null));
    });

    testWidgets('the average in the summary reads as a percentage, and tests are counted once', (tester) async {
      _screen(tester, const Size(1400, 1000));
      final fake = FakeReportRepository(
        resultsByKind: {
          ReportKind.studentPerformance: _students([_student(id: 1)]),
        },
      );
      await tester.pumpWidget(_wrap(fake, link: const ReportLink(kind: ReportKind.studentPerformance)));
      await tester.pumpAndSettle();

      expect(find.text('70.3%'), findsOneWidget);
      expect(find.text('Tests Held'), findsOneWidget);
    });

    testWidgets('a school graded by percentage gets no empty GPA column', (tester) async {
      _screen(tester, const Size(1400, 1000));
      final fake = FakeReportRepository(
        resultsByKind: {
          ReportKind.studentPerformance: _students([_student(id: 1)]),
        },
      );
      await tester.pumpWidget(_wrap(fake, link: const ReportLink(kind: ReportKind.studentPerformance)));
      await tester.pumpAndSettle();

      expect(find.text('GPA'), findsNothing);
      expect(find.text('Average'), findsOneWidget);
    });

    testWidgets('on a grade-point scale the GPA is shown', (tester) async {
      _screen(tester, const Size(1600, 1000));
      final fake = FakeReportRepository(
        resultsByKind: {
          ReportKind.studentPerformance: _students([_student(id: 1, grading: 'gpa', average: 85, grade: 'B1', gpa: 9)]),
        },
      );
      await tester.pumpWidget(_wrap(fake, link: const ReportLink(kind: ReportKind.studentPerformance)));
      await tester.pumpAndSettle();

      expect(find.text('GPA'), findsOneWidget);
      expect(find.text('9'), findsWidgets);
      expect(find.text('B1'), findsOneWidget);
    });

    testWidgets('graded "grades only", the grade is shown and no percentages', (tester) async {
      _screen(tester, const Size(1600, 1000));
      final fake = FakeReportRepository(
        resultsByKind: {
          ReportKind.studentPerformance: _students([_student(id: 1, grading: 'grades', average: null, grade: 'Good')]),
        },
      );
      await tester.pumpWidget(_wrap(fake, link: const ReportLink(kind: ReportKind.studentPerformance)));
      await tester.pumpAndSettle();

      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Average'), findsNothing);
      expect(find.text('Class average'), findsNothing);
    });
  });
}
