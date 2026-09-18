import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../data/models/app_user.dart';
import '../data/user_repository.dart';

final userListNotifierProvider = AsyncNotifierProvider<UserListNotifier, PagedList<AppUser>>(UserListNotifier.new);

class UserListNotifier extends AsyncNotifier<PagedList<AppUser>> {
  /// Set only by a SUPER_ADMIN via [setSchoolFilter] - every other role is
  /// already scoped to their own school server-side.
  int? _schoolId;
  int _page = 1;
  int _perPage = 20;

  @override
  Future<PagedList<AppUser>> build() => _fetch();

  Future<PagedList<AppUser>> _fetch() async {
    final response = await ref
        .read(userRepositoryProvider)
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

  Future<void> createUser({
    required String firstName,
    required String lastName,
    required String email,
    String? mobile,
    required String password,
    required UserRole role,
    int? schoolId,
  }) async {
    await ref
        .read(userRepositoryProvider)
        .create(
          firstName: firstName,
          lastName: lastName,
          email: email,
          mobile: mobile,
          password: password,
          role: role,
          schoolId: schoolId,
        );
    _page = 1;
    await refresh();
  }

  Future<void> updateUser(
    AppUser user, {
    String? firstName,
    String? lastName,
    String? email,
    String? mobile,
    String? password,
    UserRole? role,
  }) async {
    final updated = await ref
        .read(userRepositoryProvider)
        .update(
          user.id,
          firstName: firstName,
          lastName: lastName,
          email: email,
          mobile: mobile,
          password: password,
          role: role,
        );

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
  }

  Future<void> unlock(AppUser user) async {
    final updated = await ref.read(userRepositoryProvider).unlock(user.id);

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
  }

  Future<void> setActive(AppUser user, bool active) async {
    final updated = await ref.read(userRepositoryProvider).setActive(user.id, active);

    state = state.whenData(
      (page) => page.withItems([for (final existing in page.items) existing.id == updated.id ? updated : existing]),
    );
  }
}
