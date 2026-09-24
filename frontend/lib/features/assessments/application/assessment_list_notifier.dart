import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/assessment_repository.dart';
import '../data/models/assessment.dart';

/// Not auto-disposed, like the other list notifiers a dialog saves through:
/// the dialog refreshes this after a save, and a disposed Ref would show an
/// internal error for a save that worked. Cleared on sign-out by
/// AuthNotifier._resetSessionScopedProviders.
final assessmentListNotifierProvider = AsyncNotifierProvider<AssessmentListNotifier, PagedList<Assessment>>(
  AssessmentListNotifier.new,
);

class AssessmentListNotifier extends AsyncNotifier<PagedList<Assessment>> {
  int? _schoolId;
  int? _termId;
  int? _sectionId;
  int? _subjectId;
  String? _status;
  String? _type;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Assessment>> build() => _fetch();

  Future<PagedList<Assessment>> _fetch() async {
    final response = await ref
        .read(assessmentRepositoryProvider)
        .listPage(
          schoolId: _schoolId,
          academicTermId: _termId,
          classSectionId: _sectionId,
          subjectId: _subjectId,
          status: _status,
          type: _type,
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

  /// Every filter change goes back to the first page: page 3 of the old
  /// filter is nobody's page 3 of the new one.
  Future<void> _refilter(void Function() change) async {
    change();
    _page = 1;
    await refresh();
  }

  Future<void> setSchoolFilter(int? schoolId) => _refilter(() => _schoolId = schoolId);

  Future<void> setTermFilter(int? termId) => _refilter(() => _termId = termId);

  Future<void> setSectionFilter(int? sectionId) => _refilter(() => _sectionId = sectionId);

  Future<void> setSubjectFilter(int? subjectId) => _refilter(() => _subjectId = subjectId);

  Future<void> setStatusFilter(String? status) => _refilter(() => _status = status);

  Future<void> setTypeFilter(String? type) => _refilter(() => _type = type);

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) => _refilter(() => _perPage = perPage);

  Future<void> createAssessment({
    required int classSectionId,
    required int subjectId,
    required int academicTermId,
    int? syllabusTopicId,
    int? gradeScaleId,
    required String type,
    required String title,
    required String maxMarks,
    String? passMarks,
    String? weightage,
    required DateTime assessmentDate,
  }) async {
    await ref
        .read(assessmentRepositoryProvider)
        .create(
          classSectionId: classSectionId,
          subjectId: subjectId,
          academicTermId: academicTermId,
          syllabusTopicId: syllabusTopicId,
          gradeScaleId: gradeScaleId,
          type: type,
          title: title,
          maxMarks: maxMarks,
          passMarks: passMarks,
          weightage: weightage,
          assessmentDate: assessmentDate,
        );
    _page = 1;
    await refresh();
  }

  Future<void> updateAssessment(
    Assessment assessment, {
    int? academicTermId,
    int? gradeScaleId,
    String? type,
    String? title,
    String? maxMarks,
    String? passMarks,
    String? weightage,
    DateTime? assessmentDate,
  }) async {
    await ref
        .read(assessmentRepositoryProvider)
        .update(
          assessment.id,
          academicTermId: academicTermId,
          gradeScaleId: gradeScaleId,
          type: type,
          title: title,
          maxMarks: maxMarks,
          passMarks: passMarks,
          weightage: weightage,
          assessmentDate: assessmentDate,
        );
    await refresh();
  }

  Future<void> deleteAssessment(Assessment assessment) async {
    await ref.read(assessmentRepositoryProvider).delete(assessment.id);
    await refresh();
  }

  Future<void> publish(Assessment assessment) async {
    await ref.read(assessmentRepositoryProvider).publish(assessment.id);
    await refresh();
  }

  Future<void> reopen(Assessment assessment) async {
    await ref.read(assessmentRepositoryProvider).reopen(assessment.id);
    await refresh();
  }
}
