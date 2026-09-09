import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models/teaching_report_summary.dart';
import '../data/teaching_report_repository.dart';

final teachingReportSummaryNotifierProvider =
    AsyncNotifierProvider<TeachingReportSummaryNotifier, TeachingReportSummary>(TeachingReportSummaryNotifier.new);

/// Today's scheduled/submitted/pending counts, scoped to the actor's own
/// visibility - a SuperAdmin can additionally filter by school.
class TeachingReportSummaryNotifier extends AsyncNotifier<TeachingReportSummary> {
  int? _schoolId;

  @override
  Future<TeachingReportSummary> build() => _fetch();

  Future<TeachingReportSummary> _fetch() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return ref.read(teachingReportRepositoryProvider).summary(schoolId: _schoolId, date: today);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
