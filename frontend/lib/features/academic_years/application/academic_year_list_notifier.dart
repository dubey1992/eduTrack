import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/academic_year_repository.dart';
import '../data/models/academic_year.dart';

final academicYearListNotifierProvider = AsyncNotifierProvider<AcademicYearListNotifier, PagedList<AcademicYear>>(
  AcademicYearListNotifier.new,
);

class AcademicYearListNotifier extends AsyncNotifier<PagedList<AcademicYear>> {
  /// Set only by a SUPER_ADMIN via [setSchoolFilter] - every other role is
  /// already scoped to their own school server-side.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<AcademicYear>> build() => _fetch();

  Future<PagedList<AcademicYear>> _fetch() async {
    final response = await ref
        .read(academicYearRepositoryProvider)
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

  Future<void> createAcademicYear({
    int? schoolId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required bool isCurrent,
  }) async {
    await ref
        .read(academicYearRepositoryProvider)
        .create(schoolId: schoolId, name: name, startDate: startDate, endDate: endDate, isCurrent: isCurrent);
    _page = 1;
    await refresh();
  }

  Future<void> updateAcademicYear(
    AcademicYear academicYear, {
    String? name,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await ref
        .read(academicYearRepositoryProvider)
        .update(academicYear.id, name: name, startDate: startDate, endDate: endDate);
    await refresh();
  }

  Future<void> setCurrent(AcademicYear academicYear) async {
    await ref.read(academicYearRepositoryProvider).setCurrent(academicYear.id);
    await refresh();
  }

  Future<void> deleteAcademicYear(AcademicYear academicYear) async {
    await ref.read(academicYearRepositoryProvider).delete(academicYear.id);
    await refresh();
  }
}
