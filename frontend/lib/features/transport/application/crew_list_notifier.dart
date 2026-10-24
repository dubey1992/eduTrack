import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../staff/data/models/staff_profile.dart';
import '../../staff/data/staff_repository.dart';
import '../../users/data/user_repository.dart';

final crewListNotifierProvider = AsyncNotifierProvider<CrewListNotifier, PagedList<StaffProfile>>(CrewListNotifier.new);

/// The people on the bus - drivers and attendants - as one list
/// (docs/driver-app.md, D10).
///
/// They are employees, so this is the staff API asked for the two crew roles
/// at once; the server narrows a Transport Manager to those roles whatever
/// is asked. Kept apart from the Teachers & Staff list's notifier because
/// the two screens page and filter independently.
class CrewListNotifier extends AsyncNotifier<PagedList<StaffProfile>> {
  static const roles = [UserRole.driver, UserRole.busAttendant];

  int? _schoolId;
  int _page = 1;
  int _perPage = 20;
  int _fetchId = 0;

  @override
  Future<PagedList<StaffProfile>> build() => _fetch();

  Future<PagedList<StaffProfile>> _fetch() async {
    final response = await ref
        .read(staffRepositoryProvider)
        .listPage(schoolId: _schoolId, roles: roles, page: _page, perPage: _perPage);

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

    if (id != _fetchId) return;
    state = result;
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

  /// Adds a crew member: the login, the employment record and, for a
  /// driver, the licence record, in one call to the server.
  Future<void> addCrew({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String mobile,
    required String employeeId,
    int? schoolId,
    required DateTime joiningDate,
    String? licenceNumber,
    DateTime? licenceExpiry,
  }) async {
    await ref
        .read(staffRepositoryProvider)
        .create(
          firstName: firstName,
          lastName: lastName,
          mobile: mobile,
          role: role,
          schoolId: schoolId,
          employeeId: employeeId,
          designation: role.label,
          joiningDate: joiningDate,
          licenceNumber: licenceNumber,
          licenceExpiry: licenceExpiry,
        );
    _page = 1;
    await refresh();
  }

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
