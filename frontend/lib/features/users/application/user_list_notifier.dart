import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../data/models/app_user.dart';
import '../data/user_repository.dart';

final userListNotifierProvider = AsyncNotifierProvider<UserListNotifier, List<AppUser>>(UserListNotifier.new);

class UserListNotifier extends AsyncNotifier<List<AppUser>> {
  @override
  Future<List<AppUser>> build() {
    return ref.read(userRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(userRepositoryProvider).list());
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
    await refresh();
  }

  Future<void> setActive(AppUser user, bool active) async {
    final updated = await ref.read(userRepositoryProvider).setActive(user.id, active);

    state = state.whenData(
      (users) => [for (final existing in users) existing.id == updated.id ? updated : existing],
    );
  }
}
