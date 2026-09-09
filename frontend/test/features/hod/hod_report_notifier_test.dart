import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/hod/application/hod_report_notifier.dart';
import 'package:edutrack_app/features/hod/data/hod_report_repository.dart';
import 'package:edutrack_app/features/hod/data/models/hod_department_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_hod_report_repository.dart';

const _report = HodDepartmentReport(
  month: '2026-08',
  schoolId: 1,
  departments: [HodReportDepartment(id: 1, name: 'Mathematics')],
  workingDays: 4,
  teacherCount: 2,
  avgAttendancePercent: 18.8,
  leaveDays: 3.5,
  lateMarks: 1,
  teachers: [],
  currentPage: 1,
  lastPage: 1,
  total: 0,
  perPage: 20,
);

const _params = HodReportParams(schoolId: null, departmentId: 1, month: '2026-08');

void main() {
  ProviderContainer makeContainer(FakeHodReportRepository fake) {
    // Riverpod's default exponential-backoff retry would keep a failed
    // build "pending" for ~30s; the error path is asserted directly instead.
    final container = ProviderContainer(
      overrides: [hodReportRepositoryProvider.overrideWithValue(fake)],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    // Keep the autoDispose family alive for the duration of each test.
    container.listen(hodReportNotifierProvider(_params), (_, _) {});
    return container;
  }

  test('build() fetches the report for the params with page 1 and 20 per page', () async {
    final fake = FakeHodReportRepository(report: _report);
    final container = makeContainer(fake);

    final result = await container.read(hodReportNotifierProvider(_params).future);

    expect(result.workingDays, 4);
    expect(result.avgAttendancePercent, 18.8);
    expect(fake.lastRequest, {'school_id': null, 'department_id': 1, 'month': '2026-08', 'page': 1, 'per_page': 20});
  });

  test('goToPage() refetches the requested page', () async {
    final fake = FakeHodReportRepository(report: _report);
    final container = makeContainer(fake);
    await container.read(hodReportNotifierProvider(_params).future);

    await container.read(hodReportNotifierProvider(_params).notifier).goToPage(3);

    expect(fake.lastRequest!['page'], 3);
    expect(container.read(hodReportNotifierProvider(_params)).hasValue, isTrue);
  });

  test('setPerPage() changes the page size and jumps back to page 1', () async {
    final fake = FakeHodReportRepository(report: _report);
    final container = makeContainer(fake);
    await container.read(hodReportNotifierProvider(_params).future);
    await container.read(hodReportNotifierProvider(_params).notifier).goToPage(2);

    await container.read(hodReportNotifierProvider(_params).notifier).setPerPage(50);

    expect(fake.lastRequest!['per_page'], 50);
    expect(fake.lastRequest!['page'], 1);
  });

  test('a repository failure surfaces as an error state', () async {
    final fake = FakeHodReportRepository(
      report: _report,
      failWith: const Failure(code: 'FORBIDDEN', message: 'You are not authorized to perform this action.'),
    );
    final container = makeContainer(fake);

    await expectLater(container.read(hodReportNotifierProvider(_params).future), throwsA(isA<Failure>()));
    expect(container.read(hodReportNotifierProvider(_params)).hasError, isTrue);
  });

  test('different params are independent provider instances', () {
    const other = HodReportParams(schoolId: null, departmentId: 1, month: '2026-07');

    expect(_params == other, isFalse);
    expect(_params == const HodReportParams(schoolId: null, departmentId: 1, month: '2026-08'), isTrue);
    expect(_params.hashCode, const HodReportParams(schoolId: null, departmentId: 1, month: '2026-08').hashCode);
  });
}
