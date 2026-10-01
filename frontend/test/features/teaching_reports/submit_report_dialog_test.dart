import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_topic.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';
import 'package:edutrack_app/features/teaching_reports/application/teaching_report_list_notifier.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/teaching_reports/presentation/widgets/submit_report_dialog.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_syllabus_topic_repository.dart';
import '../../support/fake_teaching_report_repository.dart';

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

const _reportDate = '2026-09-08';

/// In the real app, TeachingReportScreen's "My Teaching Today" section
/// watches this exact family instance (same teacherId/reportDate) the whole
/// time the dialog is open above it, which is what keeps this autoDispose
/// provider alive across the dialog's await chain. This test stands the
/// dialog up on its own, so it has to hold that same watch itself -
/// otherwise the provider gets torn down mid-submit and the dialog would
/// see a spurious failure that could never happen with the real screen
/// behind it.
const _topics = [
  SyllabusTopic(id: 1, schoolId: 1, subjectId: 3, subjectName: 'Mathematics', title: 'Vectors', sequenceNumber: 1),
  SyllabusTopic(id: 2, schoolId: 1, subjectId: 3, subjectName: 'Mathematics', title: 'Trigonometry', sequenceNumber: 2),
];

Widget wrap(FakeTeachingReportRepository fake, {List<SyllabusTopic> topics = _topics}) {
  return ProviderScope(
    overrides: [
      teachingReportRepositoryProvider.overrideWithValue(fake),
      syllabusTopicRepositoryProvider.overrideWithValue(FakeSyllabusTopicRepository(topics: topics)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(
              teachingReportListNotifierProvider(
                const TeachingReportListParams(teacherId: 20, reportDate: _reportDate),
              ),
            );
            return Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const SubmitReportDialog(entry: _entry, reportDate: _reportDate),
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when topic taught is left empty', (tester) async {
    await tester.pumpWidget(wrap(FakeTeachingReportRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();

    expect(find.text('Topic taught is required'), findsOneWidget);
  });

  testWidgets('submits successfully and closes the dialog', (tester) async {
    final fake = FakeTeachingReportRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic taught'), 'Fractions');
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();

    expect(fake.lastStorePayload, isNotNull);
    expect(fake.lastStorePayload!['topic_taught'], 'Fractions');
    expect(find.byType(SubmitReportDialog), findsNothing);
    expect(find.text('Report submitted.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeTeachingReportRepository(
      failStoreWith: const Failure(code: 'TEACHING_REPORT_ALREADY_SUBMITTED', message: 'Already submitted.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Topic taught'), 'Fractions');
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();

    expect(find.text('Already submitted.'), findsOneWidget);
    expect(find.byType(SubmitReportDialog), findsOneWidget);
  });

  group('the syllabus topic', () {
    testWidgets("offers the subject's topics, and ticking one goes with the report", (tester) async {
      final fake = FakeTeachingReportRepository();
      await tester.pumpWidget(wrap(fake));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Syllabus topic (optional)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-syllabus-topic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trigonometry').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Topic taught'), 'Sine and cosine');
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();

      expect(fake.lastStorePayload?['syllabus_topic_id'], 2);
      expect(fake.lastStorePayload?['topic_taught'], 'Sine and cosine');
    });

    testWidgets('a lesson that is no chapter sends no topic', (tester) async {
      final fake = FakeTeachingReportRepository();
      await tester.pumpWidget(wrap(fake));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // "Not a syllabus topic" is the default, so a revision period or a
      // test files exactly as it did before the picker existed.
      await tester.enterText(find.widgetWithText(TextFormField, 'Topic taught'), 'Revision');
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();

      expect(fake.lastStorePayload?['syllabus_topic_id'], isNull);
      expect(fake.lastStorePayload?['topic_taught'], 'Revision');
    });

    testWidgets('a subject with no syllabus shows no picker at all', (tester) async {
      await tester.pumpWidget(wrap(FakeTeachingReportRepository(), topics: const []));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Syllabus topic (optional)'), findsNothing);
      // And the report can still be filed.
      expect(find.widgetWithText(TextFormField, 'Topic taught'), findsOneWidget);
    });

    testWidgets('a syllabus that will not load does not stop a report being filed', (tester) async {
      final fake = FakeTeachingReportRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            teachingReportRepositoryProvider.overrideWithValue(fake),
            syllabusTopicRepositoryProvider.overrideWithValue(_BrokenSyllabusRepository()),
          ],
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(
                    teachingReportListNotifierProvider(
                      const TeachingReportListParams(teacherId: 20, reportDate: _reportDate),
                    ),
                  );
                  return Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const SubmitReportDialog(entry: _entry, reportDate: _reportDate),
                      ),
                      child: const Text('Open'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Topic taught'), 'Linear equations');
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();

      expect(fake.lastStorePayload?['topic_taught'], 'Linear equations');
    });
  });
}

/// A syllabus the server will not hand over. Filing a report must not
/// depend on it.
class _BrokenSyllabusRepository extends FakeSyllabusTopicRepository {
  @override
  Future<List<SyllabusTopic>> list({required int subjectId}) async {
    throw const Failure(code: 'SERVER_ERROR', message: 'nope');
  }
}
