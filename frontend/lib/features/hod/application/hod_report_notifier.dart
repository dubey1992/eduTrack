import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hod_report_repository.dart';
import '../data/models/hod_department_report.dart';

/// The filter slice one report view is looking at. Changing any of these
/// creates a new provider instance, so paging never leaks between two
/// different months/departments (same convention as TeachingReportListParams).
class HodReportParams {
  const HodReportParams({this.schoolId, this.departmentId, required this.month});

  final int? schoolId;
  final int? departmentId;

  /// `yyyy-MM`, the backend's accepted format.
  final String month;

  @override
  bool operator ==(Object other) =>
      other is HodReportParams &&
      other.schoolId == schoolId &&
      other.departmentId == departmentId &&
      other.month == month;

  @override
  int get hashCode => Object.hash(schoolId, departmentId, month);
}

final hodReportNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<HodReportNotifier, HodDepartmentReport, HodReportParams>(HodReportNotifier.new);

class HodReportNotifier extends AsyncNotifier<HodDepartmentReport> {
  HodReportNotifier(this.params);

  final HodReportParams params;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<HodDepartmentReport> build() => _fetch();

  Future<HodDepartmentReport> _fetch() {
    return ref
        .read(hodReportRepositoryProvider)
        .departmentReport(
          schoolId: params.schoolId,
          departmentId: params.departmentId,
          month: params.month,
          page: _page,
          perPage: _perPage,
        );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }
}
