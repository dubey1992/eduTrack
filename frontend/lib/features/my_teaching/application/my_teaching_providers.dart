import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../assessments/data/assessment_repository.dart';
import '../../assessments/data/models/assessment.dart';
import '../../assessments/data/models/assessment_setup.dart';
import '../../syllabus/data/models/my_syllabus_class.dart';
import '../../syllabus/data/models/syllabus_topic.dart';
import '../../syllabus/data/syllabus_progress_repository.dart';
import '../../syllabus/data/syllabus_topic_repository.dart';
import '../../teaching_reports/data/models/teaching_report.dart';
import '../../teaching_reports/data/teaching_report_repository.dart';
import '../../today/application/today_notifier.dart';

/// The teacher's own teaching reports, newest first, a page at a time.
class MyReports {
  const MyReports({required this.items, required this.hasMore, required this.page});

  final List<TeachingReport> items;
  final bool hasMore;
  final int page;
}

/// No automatic retry: the screens have their own.
final myReportsProvider = AsyncNotifierProvider.autoDispose<MyReportsNotifier, MyReports>(
  MyReportsNotifier.new,
  retry: (retryCount, error) => null,
);

/// "Reports" in the School365ai app (docs/teacher-app.md, T3).
///
/// Always the caller's own (`mine=1`), whatever else their role lets them
/// see on the website - an HOD's department, an admin's school. Filing goes
/// through the same endpoint and rules as the web: one report per period
/// and date, nothing dated ahead, only the teacher's own periods.
class MyReportsNotifier extends AsyncNotifier<MyReports> {
  static const perPage = 20;

  @override
  Future<MyReports> build() => _page(1, const []);

  Future<MyReports> _page(int page, List<TeachingReport> before) async {
    final response = await ref.read(teachingReportRepositoryProvider).list(mine: true, page: page, perPage: perPage);

    return MyReports(
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

/// Files a report and tells the screens that show it: Today's period card
/// and the Reports list. Throws the server's [Failure] for the form.
final fileReportProvider = Provider<FileReport>(FileReport.new);

class FileReport {
  FileReport(this._ref);

  final Ref _ref;

  Future<TeachingReport> call({
    required int timetableEntryId,
    required String reportDate,
    required String topicTaught,
    int? syllabusTopicId,
    String? homework,
    String? remarks,
  }) async {
    final report = await _ref
        .read(teachingReportRepositoryProvider)
        .store(
          timetableEntryId: timetableEntryId,
          reportDate: reportDate,
          topicTaught: topicTaught,
          syllabusTopicId: syllabusTopicId,
          homework: homework,
          remarks: remarks,
        );
    _ref.invalidate(todayProvider);
    _ref.invalidate(myReportsProvider);
    // A named topic was ticked off for the class too.
    if (syllabusTopicId != null) _ref.invalidate(mySyllabusProvider);
    return report;
  }
}

/// One report, opened from its period on Today or from the list.
final myReportProvider = FutureProvider.autoDispose.family<TeachingReport, int>(
  (ref, id) => ref.read(teachingReportRepositoryProvider).get(id),
  retry: (retryCount, error) => null,
);

/// The classes and subjects the teacher teaches this year, with progress.
final mySyllabusProvider = FutureProvider.autoDispose<List<MySyllabusClass>>(
  (ref) => ref.read(syllabusProgressRepositoryProvider).mine(),
  retry: (retryCount, error) => null,
);

/// A subject's topics, for the report form's "Syllabus topic" choice.
final subjectTopicsProvider = FutureProvider.autoDispose.family<List<SyllabusTopic>, int>(
  (ref, subjectId) => ref.read(syllabusTopicRepositoryProvider).list(subjectId: subjectId),
  retry: (retryCount, error) => null,
);

/// The class tests of the classes the teacher teaches, newest first.
class MyTests {
  const MyTests({required this.items, required this.hasMore, required this.page});

  final List<Assessment> items;
  final bool hasMore;
  final int page;
}

/// "Marks" in the School365ai app (docs/teacher-app.md, T5): always the
/// caller's own classes (`mine=1`), whatever else an HOD or admin may see.
final myTestsProvider = AsyncNotifierProvider.autoDispose<MyTestsNotifier, MyTests>(
  MyTestsNotifier.new,
  retry: (retryCount, error) => null,
);

class MyTestsNotifier extends AsyncNotifier<MyTests> {
  static const perPage = 20;

  @override
  Future<MyTests> build() => _page(1, const []);

  Future<MyTests> _page(int page, List<Assessment> before) async {
    final response = await ref.read(assessmentRepositoryProvider).listPage(mine: true, page: page, perPage: perPage);

    return MyTests(
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

/// What the New test form chooses from.
final assessmentSetupProvider = FutureProvider.autoDispose<AssessmentSetup>(
  (ref) => ref.read(assessmentRepositoryProvider).setup(),
  retry: (retryCount, error) => null,
);
