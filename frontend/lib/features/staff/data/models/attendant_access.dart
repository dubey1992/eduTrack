/// How a Bus Attendant signs in, as an administrator sees it: the mobile
/// number, whether a passcode has been chosen, a lock after five wrong tries,
/// a setup code still waiting to be used, and the phones registered to them.
///
/// Never the passcode or the setup code itself - the API only says whether
/// they are set. See docs/maps.md, "The Bus Attendant".
class AttendantAccess {
  const AttendantAccess({
    required this.loginMobile,
    required this.hasPasscode,
    required this.isLocked,
    required this.setupCodePending,
    required this.setupCodeExpiresAt,
    required this.devices,
  });

  factory AttendantAccess.fromJson(Map<String, dynamic> json) {
    return AttendantAccess(
      loginMobile: json['login_mobile'] as String,
      hasPasscode: json['has_passcode'] as bool,
      isLocked: json['is_locked'] as bool,
      setupCodePending: json['setup_code_pending'] as bool,
      setupCodeExpiresAt: json['setup_code_expires_at'] as String?,
      devices: ((json['devices'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(AttendantDevice.fromJson)
          .toList(),
    );
  }

  /// E.164, e.g. `+919876543210` - the number typed on the phone to sign in.
  final String loginMobile;
  final bool hasPasscode;

  /// Five wrong passcodes lock the account until an administrator unlocks it.
  final bool isLocked;
  final bool setupCodePending;

  /// A UTC instant; null when no code is waiting.
  final String? setupCodeExpiresAt;
  final List<AttendantDevice> devices;

  AttendantAccess copyWith({bool? isLocked}) {
    return AttendantAccess(
      loginMobile: loginMobile,
      hasPasscode: hasPasscode,
      isLocked: isLocked ?? this.isLocked,
      setupCodePending: setupCodePending,
      setupCodeExpiresAt: setupCodeExpiresAt,
      devices: devices,
    );
  }
}

/// A phone registered to an attendant. A removed (revoked) one stays in the
/// list so the history is visible, but can no longer sign in.
class AttendantDevice {
  const AttendantDevice({
    required this.id,
    required this.name,
    required this.registeredAt,
    required this.lastUsedAt,
    required this.revokedAt,
    required this.isActive,
  });

  factory AttendantDevice.fromJson(Map<String, dynamic> json) {
    return AttendantDevice(
      id: json['id'] as int,
      name: json['name'] as String?,
      registeredAt: json['registered_at'] as String?,
      lastUsedAt: json['last_used_at'] as String?,
      revokedAt: json['revoked_at'] as String?,
      isActive: json['is_active'] as bool,
    );
  }

  final int id;

  /// What the phone called itself when it was registered; may be missing.
  final String? name;

  /// UTC instants.
  final String? registeredAt;
  final String? lastUsedAt;
  final String? revokedAt;
  final bool isActive;

  String get displayName => (name == null || name!.trim().isEmpty) ? 'Unnamed phone' : name!;
}

/// A freshly issued one-time setup code. The API shows it exactly once.
class AttendantSetupCode {
  const AttendantSetupCode({required this.setupCode, required this.expiresAt, required this.loginMobile});

  factory AttendantSetupCode.fromJson(Map<String, dynamic> json) {
    return AttendantSetupCode(
      setupCode: json['setup_code'] as String,
      expiresAt: json['expires_at'] as String,
      loginMobile: json['login_mobile'] as String,
    );
  }

  final String setupCode;

  /// A UTC instant.
  final String expiresAt;
  final String loginMobile;
}
