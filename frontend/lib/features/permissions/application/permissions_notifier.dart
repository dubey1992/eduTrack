import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/permissions_matrix.dart';
import '../data/permissions_repository.dart';

final permissionsNotifierProvider = AsyncNotifierProvider<PermissionsNotifier, PermissionsMatrix>(
  PermissionsNotifier.new,
);

/// The platform-wide permissions matrix, as the Permissions screen sees it.
///
/// A failed save or reset leaves the loaded matrix in place and lets the
/// error through to the screen, which keeps the edits on show; only a failed
/// load puts the whole screen into its error state.
class PermissionsNotifier extends AsyncNotifier<PermissionsMatrix> {
  @override
  Future<PermissionsMatrix> build() => ref.read(permissionsRepositoryProvider).get();

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(permissionsRepositoryProvider).get());
  }

  /// Sends only the cells in [changes] and replaces the matrix with what
  /// comes back.
  Future<void> save(LevelGrid changes) async {
    final saved = await ref.read(permissionsRepositoryProvider).save(changes);
    state = AsyncData(saved);
  }

  /// Puts every cell back to its default.
  Future<void> reset() async {
    final reset = await ref.read(permissionsRepositoryProvider).reset();
    state = AsyncData(reset);
  }
}
