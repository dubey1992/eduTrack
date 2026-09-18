import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/signed_in_session.dart';
import '../data/session_repository.dart';

final signedInSessionsNotifierProvider =
    AsyncNotifierProvider.autoDispose<SignedInSessionsNotifier, List<SignedInSession>>(SignedInSessionsNotifier.new);

/// The signed-in person's own sessions, and signing some of them out.
class SignedInSessionsNotifier extends AsyncNotifier<List<SignedInSession>> {
  @override
  Future<List<SignedInSession>> build() => ref.read(sessionRepositoryProvider).list();

  Future<void> signOut(int sessionId) async {
    await ref.read(sessionRepositoryProvider).signOut(sessionId);
    await _reload();
  }

  /// Returns how many devices were signed out.
  Future<int> signOutOthers() async {
    final ended = await ref.read(sessionRepositoryProvider).signOutOthers();
    await _reload();

    return ended;
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(() => ref.read(sessionRepositoryProvider).list());
  }
}
