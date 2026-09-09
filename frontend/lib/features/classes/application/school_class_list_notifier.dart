import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/school_class.dart';
import '../data/school_class_repository.dart';

final schoolClassListNotifierProvider = AsyncNotifierProvider<SchoolClassListNotifier, PagedList<SchoolClass>>(
  SchoolClassListNotifier.new,
);

class SchoolClassListNotifier extends AsyncNotifier<PagedList<SchoolClass>> {
  /// Set only by a SUPER_ADMIN via [setSchoolFilter] - every other role is
  /// already scoped to their own school server-side.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<SchoolClass>> build() => _fetch();

  Future<PagedList<SchoolClass>> _fetch() async {
    final response = await ref
        .read(schoolClassRepositoryProvider)
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

  Future<void> createClass({
    int? schoolId,
    required int academicYearId,
    required String name,
    required int level,
  }) async {
    await ref
        .read(schoolClassRepositoryProvider)
        .create(schoolId: schoolId, academicYearId: academicYearId, name: name, level: level);
    _page = 1;
    await refresh();
  }

  Future<void> updateClass(SchoolClass schoolClass, {String? name, int? level}) async {
    await ref.read(schoolClassRepositoryProvider).update(schoolClass.id, name: name, level: level);
    await refresh();
  }

  Future<void> deleteClass(SchoolClass schoolClass) async {
    await ref.read(schoolClassRepositoryProvider).delete(schoolClass.id);
    await refresh();
  }

  Future<void> addSection({
    required SchoolClass schoolClass,
    required String name,
    String? roomNumber,
    int? classTeacherId,
  }) async {
    await ref
        .read(schoolClassRepositoryProvider)
        .addSection(schoolClassId: schoolClass.id, name: name, roomNumber: roomNumber, classTeacherId: classTeacherId);
    await refresh();
  }

  Future<void> updateSection(ClassSection section, {String? name, String? roomNumber, int? classTeacherId}) async {
    await ref
        .read(schoolClassRepositoryProvider)
        .updateSection(section.id, name: name, roomNumber: roomNumber, classTeacherId: classTeacherId);
    await refresh();
  }

  Future<void> deleteSection(ClassSection section) async {
    await ref.read(schoolClassRepositoryProvider).deleteSection(section.id);
    await refresh();
  }
}
