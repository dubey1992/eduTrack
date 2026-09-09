import 'package:edutrack_app/features/teaching_reports/application/teaching_report_summary_notifier.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report_summary.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_teaching_report_repository.dart';

void main() {
  test('build() loads todays scheduled/submitted/pending counts', () async {
    final fake = FakeTeachingReportRepository(
      summaryData: const TeachingReportSummary(scheduled: 4, submitted: 3, pending: 1),
    );
    final container = ProviderContainer(overrides: [teachingReportRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);

    final result = await container.read(teachingReportSummaryNotifierProvider.future);

    expect(result.scheduled, 4);
    expect(result.submitted, 3);
    expect(result.pending, 1);
  });

  test('setSchoolFilter() refetches the summary', () async {
    final fake = FakeTeachingReportRepository(
      summaryData: const TeachingReportSummary(scheduled: 2, submitted: 2, pending: 0),
    );
    final container = ProviderContainer(overrides: [teachingReportRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    await container.read(teachingReportSummaryNotifierProvider.future);

    await container.read(teachingReportSummaryNotifierProvider.notifier).setSchoolFilter(3);

    final state = container.read(teachingReportSummaryNotifierProvider).value!;
    expect(state.scheduled, 2);
  });
}
