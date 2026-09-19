import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';
import '../data/models/profile.dart';
import '../data/profile_repository.dart';

final profileNotifierProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);

/// The signed-in user's own profile.
///
/// A failed change leaves the loaded profile in place and lets the error
/// through to the form, which knows which field to point at; only a failed
/// load puts the whole screen into its error state. Every successful change
/// re-reads the session too, so the header's name and photo follow at once.
class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() => ref.read(profileRepositoryProvider).get();

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(profileRepositoryProvider).get());
  }

  /// Sends only the fields that differ from the loaded profile; an empty
  /// mobile or address clears it. Nothing is sent when nothing changed.
  Future<void> updateDetails({String? firstName, String? lastName, String? mobile, String? address}) async {
    final current = state.requireValue;
    final changes = <String, String>{
      if (firstName != null && firstName != current.firstName) 'first_name': firstName,
      if (lastName != null && lastName != current.lastName) 'last_name': lastName,
      if (mobile != null && mobile != (current.mobile ?? '')) 'mobile': mobile,
      if (address != null && address != (current.address ?? '')) 'address': address,
    };
    if (changes.isEmpty) return;

    await _apply(() => ref.read(profileRepositoryProvider).update(changes));
  }

  /// On success the server signs every other session out.
  Future<void> changeEmail({required String email, required String currentPassword}) {
    return _apply(
      () => ref.read(profileRepositoryProvider).changeEmail(email: email, currentPassword: currentPassword),
    );
  }

  Future<void> uploadPhoto({required List<int> bytes, required String fileName}) {
    return _apply(() => ref.read(profileRepositoryProvider).uploadPhoto(bytes: bytes, fileName: fileName));
  }

  Future<void> removePhoto() => _apply(() => ref.read(profileRepositoryProvider).removePhoto());

  Future<void> _apply(Future<Profile> Function() change) async {
    state = AsyncData(await change());
    await ref.read(authNotifierProvider.notifier).refreshSession();
  }
}
