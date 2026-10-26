import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/date_format.dart';
import '../../hod/data/hod_report_repository.dart';
import '../../hod/data/models/hod_department_report.dart';
import '../../my_teaching/application/my_teaching_providers.dart';
import '../../staff_attendance/data/models/staff_attendance_register.dart';
import '../../staff_attendance/data/staff_attendance_repository.dart';
import '../../teaching_reports/data/models/teaching_report.dart';
import '../../teaching_reports/data/teaching_report_repository.dart';
import '../../today/application/today_notifier.dart';

/// The department's reports nobody has reviewed yet, a page at a time.
class ReviewQueue {
  const ReviewQueue({required this.items, required this.hasMore, required this.page});

  final List<TeachingReport> items;
  final bool hasMore;
  final int page;
}

/// The HOD's queue in the Department tab (docs/teacher-app.md, T7): the
/// server decides whose reports these are (`to_review=1` - the department's,
/// never the HOD's own).
final reviewQueueProvider = AsyncNotifierProvider.autoDispose<ReviewQueueNotifier, ReviewQueue>(
  ReviewQueueNotifier.new,
  retry: (retryCount, error) => null,
);

class ReviewQueueNotifier extends AsyncNotifier<ReviewQueue> {
  static const perPage = 20;

  @override
  Future<ReviewQueue> build() => _page(1, const []);

  Future<ReviewQueue> _page(int page, List<TeachingReport> before) async {
    final response = await ref
        .read(teachingReportRepositoryProvider)
        .list(toReview: true, page: page, perPage: perPage);

    return ReviewQueue(
      items: [...before, ...response.items],
      hasMore: response.currentPage < response.lastPage,
      page: response.currentPage,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore) return;

    state = await AsyncValue.guard(() => _page(current.page + 1, current.items));
  }
}

/// Marks a report reviewed and refreshes what shows it. Throws the server's
/// Failure - already reviewed, not in the HOD's department.
final reviewReportProvider = Provider<ReviewReport>(ReviewReport.new);

class ReviewReport {
  ReviewReport(this._ref);

  final Ref _ref;

  Future<TeachingReport> call(int reportId) async {
    final reviewed = await _ref.read(teachingReportRepositoryProvider).review(reportId);
    _ref.invalidate(reviewQueueProvider);
    _ref.invalidate(myReportProvider(reportId));
    _ref.invalidate(departmentMonthProvider);
    return reviewed;
  }
}

/// Sends a report back to its teacher with a note. Throws the server's
/// Failure - already reviewed, already sent back, not the department's.
final sendBackReportProvider = Provider<SendBackReport>(SendBackReport.new);

class SendBackReport {
  SendBackReport(this._ref);

  final Ref _ref;

  Future<TeachingReport> call(int reportId, String note) async {
    final returned = await _ref.read(teachingReportRepositoryProvider).sendBack(reportId, note: note);
    _ref.invalidate(reviewQueueProvider);
    _ref.invalidate(myReportProvider(reportId));
    return returned;
  }
}

/// The department's staff register for the school's today - the date Today
/// has from the server, not the phone's.
final staffTodayProvider = FutureProvider.autoDispose<StaffAttendanceRegister>((ref) async {
  final day = await ref.watch(todayProvider.future);
  return ref.read(staffAttendanceRepositoryProvider).register(date: apiDate(day.date));
}, retry: (retryCount, error) => null);

/// This month for each teacher of the department - the web's HOD report.
final departmentMonthProvider = FutureProvider.autoDispose<HodDepartmentReport>((ref) async {
  final day = await ref.watch(todayProvider.future);
  return ref
      .read(hodReportRepositoryProvider)
      .departmentReport(month: DateFormat('yyyy-MM').format(day.date), page: 1, perPage: 100);
}, retry: (retryCount, error) => null);
