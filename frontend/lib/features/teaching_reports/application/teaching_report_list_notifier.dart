import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/teaching_report.dart';
import '../data/teaching_report_repository.dart';
import 'teaching_report_summary_notifier.dart';

/// A fixed slice of the teaching-reports list - exactly one of
/// [teacherId]/[reportDate] is set for "my schedule today", both null (plus
/// an optional [schoolId]) for the "reports to review" feed. Changing a
/// filter creates a new provider instance (see the family key), so
/// pagination state never leaks between two differently-filtered views on
/// the same screen.
class TeachingReportListParams {
  const TeachingReportListParams({this.schoolId, this.teacherId, this.reportDate});

  final int? schoolId;
  final int? teacherId;
  final String? reportDate;

  @override
  bool operator ==(Object other) =>
      other is TeachingReportListParams &&
      other.schoolId == schoolId &&
      other.teacherId == teacherId &&
      other.reportDate == reportDate;

  @override
  int get hashCode => Object.hash(schoolId, teacherId, reportDate);
}

final teachingReportListNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<TeachingReportListNotifier, PagedList<TeachingReport>, TeachingReportListParams>(
      TeachingReportListNotifier.new,
    );

class TeachingReportListNotifier extends AsyncNotifier<PagedList<TeachingReport>> {
  TeachingReportListNotifier(this.params);

  final TeachingReportListParams params;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<TeachingReport>> build() => _fetch();

  Future<PagedList<TeachingReport>> _fetch() async {
    final response = await ref
        .read(teachingReportRepositoryProvider)
        .list(
          schoolId: params.schoolId,
          teacherId: params.teacherId,
          reportDate: params.reportDate,
          page: _page,
          perPage: _perPage,
        );

    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
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

  Future<TeachingReport> submit({
    required int timetableEntryId,
    required String reportDate,
    required String topicTaught,
    String? homework,
    String? remarks,
  }) async {
    final created = await ref
        .read(teachingReportRepositoryProvider)
        .store(
          timetableEntryId: timetableEntryId,
          reportDate: reportDate,
          topicTaught: topicTaught,
          homework: homework,
          remarks: remarks,
        );
    await refresh();
    ref.invalidate(teachingReportSummaryNotifierProvider);
    return created;
  }

  Future<void> review(TeachingReport report) async {
    final updated = await ref.read(teachingReportRepositoryProvider).review(report.id);
    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
    ref.invalidate(teachingReportSummaryNotifierProvider);
  }
}
