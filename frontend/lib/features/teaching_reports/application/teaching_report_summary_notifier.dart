import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/teaching_report_summary.dart';
import '../data/teaching_report_repository.dart';
import '../../auth/application/school_clock_provider.dart';

final teachingReportSummaryNotifierProvider =
    AsyncNotifierProvider<TeachingReportSummaryNotifier, TeachingReportSummary>(TeachingReportSummaryNotifier.new);

/// Today's scheduled/submitted/pending counts, scoped to the actor's own
/// visibility - a SuperAdmin can additionally filter by school.
class TeachingReportSummaryNotifier extends AsyncNotifier<TeachingReportSummary> {
  int? _schoolId;

  @override
  Future<TeachingReportSummary> build() => _fetch();

  Future<TeachingReportSummary> _fetch() {
    // "Today" here is the school's day; see SchoolClock.
    final today = ref.read(schoolClockProvider).todayIso;
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
