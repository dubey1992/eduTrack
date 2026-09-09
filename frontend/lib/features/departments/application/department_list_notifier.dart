import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/department_repository.dart';
import '../data/models/department.dart';

/// The unpaginated "every department" list - used as a picker source (e.g.
/// the Staff screen's department filter), where truncating to one page
/// would silently hide real departments. The Departments management screen
/// itself uses [departmentPageNotifierProvider] below instead.
final departmentListNotifierProvider = AsyncNotifierProvider<DepartmentListNotifier, List<Department>>(
  DepartmentListNotifier.new,
);

class DepartmentListNotifier extends AsyncNotifier<List<Department>> {
  @override
  Future<List<Department>> build() {
    return ref.read(departmentRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(departmentRepositoryProvider).list());
  }
}

final departmentPageNotifierProvider = AsyncNotifierProvider<DepartmentPageNotifier, PagedList<Department>>(
  DepartmentPageNotifier.new,
);

/// The paginated view behind the Departments management screen.
class DepartmentPageNotifier extends AsyncNotifier<PagedList<Department>> {
  /// Set only by a SUPER_ADMIN via [setSchoolFilter] - every other role is
  /// already scoped to their own school server-side.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<Department>> build() => _fetch();

  Future<PagedList<Department>> _fetch() async {
    final response = await ref
        .read(departmentRepositoryProvider)
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

  Future<void> createDepartment({int? schoolId, required String name, int? hodUserId}) async {
    await ref.read(departmentRepositoryProvider).create(schoolId: schoolId, name: name, hodUserId: hodUserId);
    _page = 1;
    await refresh();
    // Keeps the Staff screen's department-filter picker in sync, since it
    // reads the separate unpaginated provider above.
    ref.invalidate(departmentListNotifierProvider);
  }

  Future<void> updateDepartment(Department department, {String? name, int? hodUserId}) async {
    await ref.read(departmentRepositoryProvider).update(department.id, name: name, hodUserId: hodUserId);
    await refresh();
    ref.invalidate(departmentListNotifierProvider);
  }

  Future<void> deleteDepartment(Department department) async {
    await ref.read(departmentRepositoryProvider).delete(department.id);
    await refresh();
    ref.invalidate(departmentListNotifierProvider);
  }
}
