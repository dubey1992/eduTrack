import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/models/student.dart';
import '../data/student_repository.dart';

final studentListNotifierProvider = AsyncNotifierProvider<StudentListNotifier, PagedList<Student>>(
  StudentListNotifier.new,
);

class StudentListNotifier extends AsyncNotifier<PagedList<Student>> {
  /// Set only by a SUPER_ADMIN via [setSchoolFilter] - every other role is
  /// already scoped to their own school server-side.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Student>> build() => _fetch();

  Future<PagedList<Student>> _fetch() async {
    final response = await ref
        .read(studentRepositoryProvider)
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

  Future<void> createStudent({
    int? schoolId,
    required int classSectionId,
    required String admissionNumber,
    required String firstName,
    required String lastName,
    String? rollNumber,
    required String guardianName,
    String? guardianMobile,
    String? address,
  }) async {
    await ref
        .read(studentRepositoryProvider)
        .create(
          schoolId: schoolId,
          classSectionId: classSectionId,
          admissionNumber: admissionNumber,
          firstName: firstName,
          lastName: lastName,
          rollNumber: rollNumber,
          guardianName: guardianName,
          guardianMobile: guardianMobile,
          address: address,
        );
    _page = 1;
    await refresh();
  }

  Future<void> updateStudent(
    Student student, {
    int? classSectionId,
    String? admissionNumber,
    String? firstName,
    String? lastName,
    String? rollNumber,
    String? guardianName,
    String? guardianMobile,
    String? address,
  }) async {
    final updated = await ref
        .read(studentRepositoryProvider)
        .update(
          student.id,
          classSectionId: classSectionId,
          admissionNumber: admissionNumber,
          firstName: firstName,
          lastName: lastName,
          rollNumber: rollNumber,
          guardianName: guardianName,
          guardianMobile: guardianMobile,
          address: address,
        );

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
  }

  Future<void> setActive(Student student, bool active) async {
    final updated = await ref.read(studentRepositoryProvider).setActive(student.id, active);

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
  }
}
