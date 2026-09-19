import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/staff/data/attendant_access_repository.dart';
import 'package:edutrack_app/features/staff/data/models/attendant_access.dart';

/// One attendant's sign-in, in memory. Issuing a code marks one pending;
/// removing a device marks it revoked, as the API does.
class FakeAttendantAccessRepository implements AttendantAccessRepository {
  FakeAttendantAccessRepository({required this.access, this.failGetWith, this.failIssueWith});

  /// What the server currently holds.
  AttendantAccess access;
  Failure? failGetWith;
  Failure? failIssueWith;
  Failure? failRemoveWith;

  int getCalls = 0;
  int issueCalls = 0;
  int? lastRemovedDeviceId;

  /// What the next setup code will be.
  String nextCode = '12345678';
  String nextExpiresAt = '2026-09-11T02:00:00.000000Z';

  @override
  Future<AttendantAccess> get(int staffProfileId) async {
    getCalls++;
    if (failGetWith != null) throw failGetWith!;
    return access;
  }

  @override
  Future<AttendantSetupCode> issueSetupCode(int staffProfileId) async {
    issueCalls++;
    if (failIssueWith != null) throw failIssueWith!;
    access = AttendantAccess(
      loginMobile: access.loginMobile,
      hasPasscode: access.hasPasscode,
      isLocked: access.isLocked,
      setupCodePending: true,
      setupCodeExpiresAt: nextExpiresAt,
      devices: access.devices,
    );
    return AttendantSetupCode(setupCode: nextCode, expiresAt: nextExpiresAt, loginMobile: access.loginMobile);
  }

  @override
  Future<AttendantAccess> removeDevice(int staffProfileId, int deviceId) async {
    if (failRemoveWith != null) throw failRemoveWith!;
    lastRemovedDeviceId = deviceId;
    access = AttendantAccess(
      loginMobile: access.loginMobile,
      hasPasscode: access.hasPasscode,
      isLocked: access.isLocked,
      setupCodePending: access.setupCodePending,
      setupCodeExpiresAt: access.setupCodeExpiresAt,
      devices: [
        for (final d in access.devices)
          d.id == deviceId
              ? AttendantDevice(
                  id: d.id,
                  name: d.name,
                  registeredAt: d.registeredAt,
                  lastUsedAt: d.lastUsedAt,
                  revokedAt: '2026-09-10T08:00:00.000000Z',
                  isActive: false,
                )
              : d,
      ],
    );
    return access;
  }

  /// What the server does when the user unlock clears the passcode lock.
  void unlockOnServer() => access = access.copyWith(isLocked: false);
}
