import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/grade_scale_repository.dart';
import '../data/models/grade_scale.dart';

/// Not auto-disposed, like the academic year list it sits beside.
///
/// The dialog saves through this notifier and then refreshes. Auto-disposing
/// it means that refresh can run against a disposed Ref whenever nothing is
/// watching the list - the screen left behind, a slow save - and the person
/// is shown an internal error for a save that actually worked. The list is a
/// handful of rows; keeping it costs nothing.
final gradeScaleListNotifierProvider = AsyncNotifierProvider<GradeScaleListNotifier, PagedList<GradeScale>>(
  GradeScaleListNotifier.new,
);

class GradeScaleListNotifier extends AsyncNotifier<PagedList<GradeScale>> {
  /// Set only by an actor who spans several schools; everybody else is
  /// scoped server-side.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<GradeScale>> build() => _fetch();

  Future<PagedList<GradeScale>> _fetch() async {
    final response = await ref
        .read(gradeScaleRepositoryProvider)
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

  Future<void> createScale({
    int? schoolId,
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) async {
    await ref
        .read(gradeScaleRepositoryProvider)
        .create(schoolId: schoolId, name: name, isDefault: isDefault, bands: bands);
    _page = 1;
    await refresh();
  }

  Future<void> updateScale(
    GradeScale scale, {
    required String name,
    required bool isDefault,
    required List<GradeBand> bands,
  }) async {
    await ref.read(gradeScaleRepositoryProvider).update(scale.id, name: name, isDefault: isDefault, bands: bands);
    await refresh();
  }

  Future<void> deleteScale(GradeScale scale) async {
    await ref.read(gradeScaleRepositoryProvider).delete(scale.id);
    await refresh();
  }
}
