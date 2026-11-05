import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../academic_years/application/viewed_year.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../data/models/quick_class_setup.dart';
import '../data/models/school_class.dart';
import '../data/school_class_repository.dart';

final quickSetupOptionsProvider = FutureProvider.autoDispose<QuickSetupOptions>(
  (ref) => ref.watch(schoolClassRepositoryProvider).quickSetupOptions(),
);

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
  Future<PagedList<SchoolClass>> build() {
    // The top bar's year (decided 2026-11-05): choosing another reloads
    // the list from page one. Its id is watched, not the year itself, so a
    // year still loading does not rebuild the list a second time.
    ref.listen(viewedYearIdProvider, (previous, next) => _page = 1);
    ref.watch(viewedYearIdProvider);
    return _fetch();
  }

  Future<PagedList<SchoolClass>> _fetch() async {
    // A Super Admin picks a school first, whose years are not the top bar's.
    final year = _schoolId == null ? await _viewedYear() : null;
    final response = await ref
        .read(schoolClassRepositoryProvider)
        .listPage(schoolId: _schoolId, academicYearId: year?.id, page: _page, perPage: _perPage);

    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
    );
  }

  /// The top bar's year, or none when the years cannot be read - the list
  /// then shows every year, as it did before there was a switch.
  Future<AcademicYear?> _viewedYear() async {
    try {
      return await ref.read(viewedYearProvider.future);
    } catch (error) {
      developer.log('Academic years unavailable; listing every year', name: 'classes', error: error);
      return null;
    }
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

  Future<QuickSetupResult> quickSetup({
    int? schoolId,
    required int academicYearId,
    required List<String> classes,
    required int sections,
  }) async {
    final result = await ref
        .read(schoolClassRepositoryProvider)
        .quickSetup(schoolId: schoolId, academicYearId: academicYearId, classes: classes, sections: sections);
    _page = 1;
    await refresh();
    return result;
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
