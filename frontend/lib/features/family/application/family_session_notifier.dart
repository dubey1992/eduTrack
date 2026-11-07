import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/session_ended_notifier.dart';
import '../data/family_auth_repository.dart';
import '../data/models/family_account.dart';

/// Who is signed in to the Family app: null when nobody is. Its own session,
/// not the staff apps' (authNotifierProvider) - a family account has no
/// staff profile, and the staff `/auth/me` refuses it.
final familySessionProvider = AsyncNotifierProvider<FamilySessionNotifier, FamilyAccount?>(FamilySessionNotifier.new);

class FamilySessionNotifier extends AsyncNotifier<FamilyAccount?> {
  @override
  Future<FamilyAccount?> build() async {
    // The server ended the session (signed out from the office, 30 days
    // unused, the app switched off): signed out here too, at once.
    ref.listen(sessionEndedProvider, (_, ended) {
      if (ended) _endedByServer();
    });

    return ref.read(familyAuthRepositoryProvider).restore();
  }

  /// A sign-in screen has signed somebody in.
  void signedIn(FamilyAccount account) {
    ref.read(sessionEndedProvider.notifier).clear();
    state = AsyncData(account);
  }

  Future<void> logout() async {
    await ref.read(familyAuthRepositoryProvider).logout();
    ref.invalidate(selectedChildIndexProvider);
    state = const AsyncData(null);
  }

  /// Fetches the account again: a child added by the school appears.
  Future<void> refresh() async {
    final account = await ref.read(familyAuthRepositoryProvider).restore();
    state = AsyncData(account);
  }

  Future<void> _endedByServer() async {
    await ref.read(familyAuthRepositoryProvider).forgetSession();
    ref.invalidate(selectedChildIndexProvider);
    state = const AsyncData(null);
  }
}

/// Which child the parent is looking at: an index into the account's
/// children, kept while the app is open.
final selectedChildIndexProvider = NotifierProvider<SelectedChildIndex, int>(SelectedChildIndex.new);

class SelectedChildIndex extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

/// The child on screen, or null for an account with no child at the school
/// (all of them have left).
final selectedChildProvider = Provider<FamilyChild?>((ref) {
  final children = ref.watch(familySessionProvider).value?.children ?? const [];
  if (children.isEmpty) return null;

  final index = ref.watch(selectedChildIndexProvider);
  return children[index.clamp(0, children.length - 1)];
});
