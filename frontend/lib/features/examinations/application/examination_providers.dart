import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../../academic_years/application/viewed_year.dart';
import '../../classes/data/models/school_class.dart';
import '../../classes/data/school_class_repository.dart';
import '../data/examination_repository.dart';
import '../data/models/examination.dart';

/// The exams of the year in view (the top bar's year), newest first.
final examinationListProvider = FutureProvider.autoDispose<PaginatedResponse<Examination>>((ref) async {
  final year = await ref.watch(viewedYearProvider.future);
  return ref.watch(examinationRepositoryProvider).list(academicYearId: year?.id);
}, retry: (retryCount, error) => null);

/// One exam with its date sheet and versions, and what can be done to it.
final examinationProvider = AsyncNotifierProvider.autoDispose.family<ExaminationNotifier, Examination, int>(
  ExaminationNotifier.new,
  retry: (retryCount, error) => null,
);

class ExaminationNotifier extends AsyncNotifier<Examination> {
  ExaminationNotifier(this.id);

  final int id;

  ExaminationRepository get _repository => ref.read(examinationRepositoryProvider);

  @override
  Future<Examination> build() => _repository.get(id);

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _repository.get(id));
  }

  /// Each of these throws the server's [Failure] for the screen to show,
  /// and on success puts the exam the server sent back in place.
  Future<void> updateDetails(Map<String, dynamic> fields) async {
    state = AsyncData(await _repository.update(id, fields));
    ref.invalidate(examinationListProvider);
  }

  Future<void> savePapers(List<ExamPaper> papers) async {
    state = AsyncData(await _repository.savePapers(id, papers));
    ref.invalidate(examinationListProvider);
  }

  Future<void> publish() async {
    state = AsyncData(await _repository.publish(id));
    ref.invalidate(examinationListProvider);
    ref.invalidate(candidatesProvider(id));
  }
}

/// The classes of an exam's year, with their sections - the date sheet's
/// class picker and the admit cards' section filter.
final examClassesProvider = FutureProvider.autoDispose.family<List<SchoolClass>, int>((ref, academicYearId) {
  return ref.watch(schoolClassRepositoryProvider).list(academicYearId: academicYearId);
});

/// What the admit-card list is narrowed to.
class CandidateFilter {
  const CandidateFilter({this.sectionId, this.query = '', this.state, this.page = 1});

  final int? sectionId;
  final String query;
  final CardState? state;
  final int page;

  CandidateFilter copyWith({int? Function()? sectionId, String? query, CardState? Function()? state, int? page}) {
    return CandidateFilter(
      sectionId: sectionId != null ? sectionId() : this.sectionId,
      query: query ?? this.query,
      state: state != null ? state() : this.state,
      page: page ?? 1,
    );
  }
}

final candidateFilterProvider = NotifierProvider.autoDispose.family<CandidateFilterNotifier, CandidateFilter, int>(
  CandidateFilterNotifier.new,
);

class CandidateFilterNotifier extends Notifier<CandidateFilter> {
  CandidateFilterNotifier(this.examId);

  final int examId;

  @override
  CandidateFilter build() => const CandidateFilter();

  void set(CandidateFilter filter) => state = filter;
}

final candidatesProvider = FutureProvider.autoDispose.family<CandidatePage, int>((ref, examId) {
  final filter = ref.watch(candidateFilterProvider(examId));
  return ref
      .watch(examinationRepositoryProvider)
      .candidates(examId, sectionId: filter.sectionId, query: filter.query, state: filter.state, page: filter.page);
}, retry: (retryCount, error) => null);
