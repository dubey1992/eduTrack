import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../users/data/user_repository.dart';
import '../data/attendant_access_repository.dart';
import '../data/models/attendant_access.dart';

/// One Bus Attendant's sign-in, keyed by their staff profile id - the state
/// behind the attendant sign-in panel.
final attendantAccessProvider = AsyncNotifierProvider.autoDispose.family<AttendantAccessNotifier, AttendantAccess, int>(
  AttendantAccessNotifier.new,
);

class AttendantAccessNotifier extends AsyncNotifier<AttendantAccess> {
  AttendantAccessNotifier(this.staffProfileId);

  final int staffProfileId;

  AttendantAccessRepository get _repository => ref.read(attendantAccessRepositoryProvider);

  @override
  Future<AttendantAccess> build() => _repository.get(staffProfileId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository.get(staffProfileId));
  }

  /// Issues a new one-time code (replacing any code still waiting) and
  /// returns it so the panel can show it once. The panel's own state is
  /// re-read afterwards, so "code pending" and its expiry are current.
  Future<AttendantSetupCode> issueSetupCode() async {
    final code = await _repository.issueSetupCode(staffProfileId);
    state = await AsyncValue.guard(() => _repository.get(staffProfileId));
    return code;
  }

  Future<void> removeDevice(AttendantDevice device) async {
    state = AsyncData(await _repository.removeDevice(staffProfileId, device.id));
  }

  /// Five wrong passcodes lock the account; this is the ordinary account
  /// unlock, which clears the passcode lock too.
  Future<void> unlock(int userId) async {
    await ref.read(userRepositoryProvider).unlock(userId);
    state = await AsyncValue.guard(() => _repository.get(staffProfileId));
  }
}
