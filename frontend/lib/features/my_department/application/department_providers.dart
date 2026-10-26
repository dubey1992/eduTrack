import '../../reports/data/models/report.dart';
import '../../reports/data/report_repository.dart';
import '../../../core/utils/date_period.dart';

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
  const ReviewQueue({required this.items, required this.hasMore, required this.page, this.period = DatePeriod.all});

  final List<TeachingReport> items;
  final bool hasMore;
  final int page;

  /// The period the list is filtered to.
  final DatePeriod period;
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

  DatePeriod _period = DatePeriod.all;

  /// The chosen period - read by the chips, which show it while loading too.
  DatePeriod get period => _period;

  @override
  Future<ReviewQueue> build() => _page(1, const []);

  Future<ReviewQueue> _page(int page, List<TeachingReport> before) async {
    final range = _period.rangeFrom(DateTime.now());
    final response = await ref
        .read(teachingReportRepositoryProvider)
        .list(toReview: true, dateFrom: range?.from, dateTo: range?.to, page: page, perPage: perPage);

    return ReviewQueue(
      items: [...before, ...response.items],
      hasMore: response.currentPage < response.lastPage,
      page: response.currentPage,
      period: _period,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Day / week / month (docs/teacher-app.md, "Filters by period").
  Future<void> setPeriod(DatePeriod period) async {
    _period = period;
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
/// The department's staff by day, week or month (docs/teacher-app.md,
/// "Filters by period"). A day is the register itself - who is in, and when
/// they arrived; a week or a month is each person's totals, from the same
/// staff attendance report the website prints, which the server narrows to
/// the HOD's own department.
class StaffView {
  const StaffView({required this.period, this.register, this.summary});

  final DatePeriod period;

  /// Set for a day.
  final StaffAttendanceRegister? register;

  /// Set for a week or a month.
  final ReportResult? summary;
}

final staffViewProvider = AsyncNotifierProvider.autoDispose<StaffViewNotifier, StaffView>(
  StaffViewNotifier.new,
  retry: (retryCount, error) => null,
);

class StaffViewNotifier extends AsyncNotifier<StaffView> {
  DatePeriod _period = DatePeriod.day;

  /// The chosen period - read by the chips, which show it while loading too.
  DatePeriod get period => _period;

  @override
  Future<StaffView> build() async {
    final period = _period;

    if (period == DatePeriod.day) {
      // The school's today, from Today, not the phone's.
      final day = await ref.watch(todayProvider.future);
      final register = await ref.read(staffAttendanceRepositoryProvider).register(date: apiDate(day.date));
      return StaffView(period: period, register: register);
    }

    // The period up to the school's today: the report refuses days still to
    // come, which nobody could have failed to mark yet.
    final day = await ref.watch(todayProvider.future);
    final range = period.rangeFrom(day.date)!;
    final summary = await ref
        .read(reportRepositoryProvider)
        .fetch(ReportKind.staffAttendance, from: range.from, to: apiDate(day.date));
    return StaffView(period: period, summary: summary);
  }

  Future<void> setPeriod(DatePeriod period) async {
    _period = period;
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }
}

/// This month for each teacher of the department - the web's HOD report.
final departmentMonthProvider = FutureProvider.autoDispose<HodDepartmentReport>((ref) async {
  final day = await ref.watch(todayProvider.future);
  return ref
      .read(hodReportRepositoryProvider)
      .departmentReport(month: DateFormat('yyyy-MM').format(day.date), page: 1, perPage: 100);
}, retry: (retryCount, error) => null);
