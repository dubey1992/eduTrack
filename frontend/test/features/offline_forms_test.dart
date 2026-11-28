import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/connection_status.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/presentation/marks_sheet_dialog.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_teaching/application/staff_outbox.dart';
import 'package:edutrack_app/features/my_teaching/data/outbox.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';
import 'package:edutrack_app/features/staff_leave/presentation/apply_leave_dialog.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';
import 'package:edutrack_app/features/teaching_reports/application/teaching_report_list_notifier.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/teaching_reports/presentation/widgets/submit_report_dialog.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_assessment_repository.dart';
import '../support/fake_auth_repository.dart';
import '../support/fake_staff_leave_repository.dart';
import '../support/fake_syllabus_topic_repository.dart';
import '../support/fake_teaching_report_repository.dart';
import '../support/fake_today_repository.dart';
import '../support/in_memory_key_value_store.dart';
import '../support/session_users.dart';

/// The web forms with no connection (docs/offline-web.md, O3): the work is
/// kept on the computer, the person is told plainly, and the form closes as
/// if sent. Any other refusal is shown in the form exactly as before.
const _entry = TimetableEntry(
  id: 5,
  schoolId: 1,
  classSectionId: 10,
  classSectionName: 'Grade 8 A',
  periodId: 1,
  periodNumber: 1,
  dayOfWeek: DayOfWeek.monday,
  subjectId: 3,
  subjectName: 'Mathematics',
  teacherId: 20,
  teacherName: 'Priya Sharma',
);

void main() {
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester,
    List<Override> overrides,
    Widget Function() dialog, {
    bool watchReports = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        offlineWorkProvider.overrideWithValue(true),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, id: 20)),
        ),
        ...overrides,
      ],
      retry: (retryCount, error) => null,
    );
    await container.read(authNotifierProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                if (watchReports) {
                  ref.watch(
                    teachingReportListNotifierProvider(
                      const TeachingReportListParams(teacherId: 20, reportDate: '2026-11-28'),
                    ),
                  );
                }
                return ElevatedButton(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => dialog()),
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// Stops the outbox's retries before the test ends.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }

  group('leave', () {
    testWidgets('with no connection the request is kept and the person told', (tester) async {
      final leave = FakeStaffLeaveRepository(failApplyWith: Failure.network());
      await pump(tester, [staffLeaveRepositoryProvider.overrideWithValue(leave)], () => const ApplyLeaveDialog());

      await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Family function');
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      expect(find.byType(ApplyLeaveDialog), findsNothing);
      expect(find.textContaining('leave request saved on this computer'), findsOneWidget);
      final kept = container.read(staffOutboxProvider).single;
      expect(kept.kind, OutboxKind.leave);
      expect(kept.payload['reason'], 'Family function');
      await finish(tester);
    });

    testWidgets('a refusal from the server stays in the form, nothing kept', (tester) async {
      final leave = FakeStaffLeaveRepository(
        failApplyWith: const Failure(
          code: 'LEAVE_OVERLAPS_EXISTING',
          message: 'You already have leave on these dates.',
        ),
      );
      await pump(tester, [staffLeaveRepositoryProvider.overrideWithValue(leave)], () => const ApplyLeaveDialog());

      await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Family function');
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      expect(find.text('You already have leave on these dates.'), findsOneWidget);
      expect(container.read(staffOutboxProvider), isEmpty);
      await finish(tester);
    });
  });

  testWidgets('a teaching report with no connection is kept, keyed to its period and day', (tester) async {
    final reports = FakeTeachingReportRepository(failStoreWith: Failure.network());
    await pump(
      tester,
      [
        teachingReportRepositoryProvider.overrideWithValue(reports),
        syllabusTopicRepositoryProvider.overrideWithValue(FakeSyllabusTopicRepository(topics: const [])),
      ],
      () => const SubmitReportDialog(entry: _entry, reportDate: '2026-11-28'),
      watchReports: true,
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic taught'), 'Fractions');
    await tester.tap(find.text('Submit Report'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('report saved on this computer'), findsOneWidget);
    final kept = container.read(staffOutboxProvider).single;
    expect(kept.key, OutboxItem.reportKey(5, '2026-11-28'));
    expect(kept.label, 'Teaching report, Mathematics, Grade 8 A, period 1');
    expect(kept.payload['topic_taught'], 'Fractions');
    await finish(tester);
  });

  testWidgets('marks with no connection are kept, and the sheet says they wait', (tester) async {
    final marks = FakeAssessmentRepository(
      sheetEntries: [fakeEntry(studentId: 1, name: 'Aarav Sharma')],
      failWith: {'saveMarks': Failure.network()},
    );
    await pump(tester, [
      assessmentRepositoryProvider.overrideWithValue(marks),
    ], () => MarksSheetDialog(assessment: fakeAssessment(id: 4), canManage: true));

    await tester.enterText(find.widgetWithText(TextField, 'Marks'), '17.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Marks'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('marks saved on this computer'), findsOneWidget);
    expect(find.byKey(const Key('marks-waiting-to-send')), findsOneWidget);
    final kept = container.read(staffOutboxProvider).single;
    expect(kept.key, OutboxItem.marksKey(4));
    expect((kept.payload['marks'] as List).single['marks_obtained'], '17.5');
    await finish(tester);
  });
}
