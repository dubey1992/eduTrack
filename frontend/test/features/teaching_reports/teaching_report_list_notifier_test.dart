import 'package:edutrack_app/features/teaching_reports/application/teaching_report_list_notifier.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_teaching_report_repository.dart';

const _report = TeachingReport(
  id: 1,
  schoolId: 1,
  timetableEntryId: 5,
  classSectionName: 'Grade 8 A',
  periodNumber: 1,
  subjectName: 'Mathematics',
  teacherId: 20,
  teacherName: 'Priya Sharma',
  reportDate: '2026-09-07',
  topicTaught: 'Fractions',
  homework: 'Exercise 4.1',
  remarks: null,
  reviewedBy: null,
  reviewedByName: null,
  reviewedAt: null,
);

void main() {
  ProviderContainer makeContainer(FakeTeachingReportRepository fake) {
    return ProviderContainer(overrides: [teachingReportRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads a teachers own reports for a given date', () async {
    final fake = FakeTeachingReportRepository(reports: [_report]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    const params = TeachingReportListParams(teacherId: 20, reportDate: '2026-09-07');
    final result = await container.read(teachingReportListNotifierProvider(params).future);

    expect(result.items, hasLength(1));
  });

  test('build() excludes reports for a different date', () async {
    final fake = FakeTeachingReportRepository(reports: [_report]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    const params = TeachingReportListParams(teacherId: 20, reportDate: '2026-09-08');
    final result = await container.read(teachingReportListNotifierProvider(params).future);

    expect(result.items, isEmpty);
  });

  test('submit() creates a report and refreshes the list', () async {
    final fake = FakeTeachingReportRepository();
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    const params = TeachingReportListParams(teacherId: 20, reportDate: '2026-09-07');
    await container.read(teachingReportListNotifierProvider(params).future);

    final created = await container
        .read(teachingReportListNotifierProvider(params).notifier)
        .submit(timetableEntryId: 5, reportDate: '2026-09-07', topicTaught: 'Fractions');

    expect(created.topicTaught, 'Fractions');
    expect(fake.lastStorePayload, isNotNull);
    final state = container.read(teachingReportListNotifierProvider(params)).value!;
    expect(state.items, hasLength(1));
  });

  test('review() marks a report reviewed in place', () async {
    final fake = FakeTeachingReportRepository(reports: [_report]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    const params = TeachingReportListParams(schoolId: 1);
    await container.read(teachingReportListNotifierProvider(params).future);

    await container.read(teachingReportListNotifierProvider(params).notifier).review(_report);

    expect(fake.lastReviewedId, 1);
    final state = container.read(teachingReportListNotifierProvider(params)).value!;
    expect(state.items.single.isReviewed, isTrue);
  });
}
