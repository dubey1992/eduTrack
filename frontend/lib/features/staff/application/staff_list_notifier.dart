import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../users/data/user_repository.dart';
import '../data/models/staff_profile.dart';
import '../data/staff_repository.dart';

final staffListNotifierProvider = AsyncNotifierProvider<StaffListNotifier, PagedList<StaffProfile>>(
  StaffListNotifier.new,
);

class StaffListNotifier extends AsyncNotifier<PagedList<StaffProfile>> {
  /// Set only by a SUPER_ADMIN via [setSchoolFilter] - every other role is
  /// already scoped to their own school server-side.
  int? _schoolId;
  int? _departmentId;
  UserRole? _role;
  String? _search;
  int _page = 1;
  int _perPage = 20;

  /// Which fetch is the current one. Two searches can be in flight at once -
  /// a slow reply for "Abhi" must not land on top of a fast one for
  /// "Abhishek" and leave the list showing the wrong answer to a question
  /// nobody asked any more.
  int _fetchId = 0;

  @override
  Future<PagedList<StaffProfile>> build() => _fetch();

  Future<PagedList<StaffProfile>> _fetch() async {
    final response = await ref
        .read(staffRepositoryProvider)
        .listPage(
          schoolId: _schoolId,
          departmentId: _departmentId,
          role: _role,
          search: _search,
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
    final id = ++_fetchId;

    state = const AsyncLoading();
    final result = await AsyncValue.guard(_fetch);

    // Something newer was asked for while this was away; it owns the state.
    if (id != _fetchId) return;
    state = result;
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> setDepartmentFilter(int? departmentId) async {
    _departmentId = departmentId;
    _page = 1;
    await refresh();
  }

  Future<void> setRoleFilter(UserRole? role) async {
    _role = role;
    _page = 1;
    await refresh();
  }

  Future<void> setSearch(String? search) async {
    _search = (search == null || search.trim().isEmpty) ? null : search.trim();
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

  Future<void> createEmployee({
    required String firstName,
    required String lastName,
    required String email,
    String? mobile,
    required String password,
    required UserRole role,
    int? schoolId,
    required String employeeId,
    int? departmentId,
    String? designation,
    required DateTime joiningDate,
    String? address,
  }) async {
    await ref
        .read(staffRepositoryProvider)
        .create(
          firstName: firstName,
          lastName: lastName,
          email: email,
          mobile: mobile,
          password: password,
          role: role,
          schoolId: schoolId,
          employeeId: employeeId,
          departmentId: departmentId,
          designation: designation,
          joiningDate: joiningDate,
          address: address,
        );
    _page = 1;
    await refresh();
  }

  Future<void> updateProfile(
    StaffProfile profile, {
    String? employeeId,
    int? departmentId,
    String? designation,
    DateTime? joiningDate,
    String? address,
  }) async {
    final updated = await ref
        .read(staffRepositoryProvider)
        .update(
          profile.id,
          employeeId: employeeId,
          departmentId: departmentId,
          designation: designation,
          joiningDate: joiningDate,
          address: address,
        );

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
  }

  /// Activation/deactivation reuses the existing Users endpoints - a
  /// staff member's account status is a User concern, not duplicated here.
  Future<void> setActive(StaffProfile profile, bool active) async {
    final updatedUser = await ref.read(userRepositoryProvider).setActive(profile.userId, active);

    state = state.whenData(
      (page) => page.withItems([
        for (final existing in page.items)
          existing.userId == updatedUser.id ? existing.copyWith(status: updatedUser.status) : existing,
      ]),
    );
  }
}
