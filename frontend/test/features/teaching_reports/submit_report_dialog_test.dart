import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/teaching_reports/application/teaching_report_list_notifier.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/teaching_reports/presentation/widgets/submit_report_dialog.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
Widget wrap(FakeTeachingReportRepository fake) {
  return ProviderScope(
    overrides: [teachingReportRepositoryProvider.overrideWithValue(fake)],
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
}
