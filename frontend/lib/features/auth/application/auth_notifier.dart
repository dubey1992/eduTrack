import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/models/authenticated_user.dart';

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthenticatedUser?>(AuthNotifier.new);

/// Holds the current session. `null` data means "no one is logged in";
/// loading/error come for free from [AsyncValue] so the UI (via
/// [AsyncValueView]) shows the right state automatically.
class AuthNotifier extends AsyncNotifier<AuthenticatedUser?> {
  @override
  Future<AuthenticatedUser?> build() {
    return ref.read(authRepositoryProvider).restoreSession();
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).login(email: email, password: password),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}
