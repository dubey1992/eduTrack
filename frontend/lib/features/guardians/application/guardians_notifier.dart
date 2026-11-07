import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/guardian_repository.dart';
import '../data/models/guardian_link.dart';

/// One student's guardians, keyed by the student - the dialog is opened per
/// student (docs/parent-student-app.md, F0).
final guardiansProvider = AsyncNotifierProvider.autoDispose.family<GuardiansNotifier, List<GuardianLink>, int>(
  GuardiansNotifier.new,
  // A failure is shown with its own retry button, not retried behind the
  // office's back.
  retry: (retryCount, error) => null,
);

class GuardiansNotifier extends AsyncNotifier<List<GuardianLink>> {
  // Riverpod 3 does not hand the key to build(), so it is a constructor field.
  GuardiansNotifier(this.studentId);

  final int studentId;

  @override
  Future<List<GuardianLink>> build() => ref.read(guardianRepositoryProvider).list(studentId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(guardianRepositoryProvider).list(studentId));
  }

  /// Takes a guardian off the student, then shows the list as it now stands.
  /// The failure, if any, is thrown back for the dialog to say.
  Future<void> unlink(GuardianLink link) async {
    await ref.read(guardianRepositoryProvider).unlink(studentId, link.id);
    await refresh();
  }
}

/// One guardian's Family app sign-in, keyed by (student, link).
final familyAccessProvider = AsyncNotifierProvider.autoDispose.family<FamilyAccessNotifier, FamilyAccess, (int, int)>(
  FamilyAccessNotifier.new,
  retry: (retryCount, error) => null,
);

class FamilyAccessNotifier extends AsyncNotifier<FamilyAccess> {
  FamilyAccessNotifier(this.key);

  final (int, int) key;

  @override
  Future<FamilyAccess> build() => ref.read(guardianRepositoryProvider).access(key.$1, key.$2);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> removePhone(FamilyPhone phone) async {
    state = AsyncData(await ref.read(guardianRepositoryProvider).removePhone(key.$1, key.$2, phone.id));
  }
}
