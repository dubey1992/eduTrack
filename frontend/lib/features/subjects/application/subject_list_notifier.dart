import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/subject.dart';
import '../data/subject_repository.dart';

final subjectListNotifierProvider = AsyncNotifierProvider<SubjectListNotifier, PagedList<Subject>>(
  SubjectListNotifier.new,
);

class SubjectListNotifier extends AsyncNotifier<PagedList<Subject>> {
  /// Set only by a SUPER_ADMIN via [setSchoolFilter] - every other role is
  /// already scoped to their own school server-side.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Subject>> build() => _fetch();

  Future<PagedList<Subject>> _fetch() async {
    final response = await ref
        .read(subjectRepositoryProvider)
        .listPage(schoolId: _schoolId, page: _page, perPage: _perPage);

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

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
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

  Future<void> createSubject({
    int? schoolId,
    required int departmentId,
    required String code,
    required String name,
    required int minClassLevel,
    required int maxClassLevel,
    int? leadTeacherId,
  }) async {
    await ref
        .read(subjectRepositoryProvider)
        .create(
          schoolId: schoolId,
          departmentId: departmentId,
          code: code,
          name: name,
          minClassLevel: minClassLevel,
          maxClassLevel: maxClassLevel,
          leadTeacherId: leadTeacherId,
        );
    _page = 1;
    await refresh();
  }

  Future<void> updateSubject(
    Subject subject, {
    int? departmentId,
    String? code,
    String? name,
    int? minClassLevel,
    int? maxClassLevel,
    int? leadTeacherId,
  }) async {
    await ref
        .read(subjectRepositoryProvider)
        .update(
          subject.id,
          departmentId: departmentId,
          code: code,
          name: name,
          minClassLevel: minClassLevel,
          maxClassLevel: maxClassLevel,
          leadTeacherId: leadTeacherId,
        );
    await refresh();
  }

  Future<void> deleteSubject(Subject subject) async {
    await ref.read(subjectRepositoryProvider).delete(subject.id);
    await refresh();
  }
}
