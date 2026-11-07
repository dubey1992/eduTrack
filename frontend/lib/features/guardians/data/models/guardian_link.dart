/// One of a student's guardians (docs/parent-student-app.md, F0).
///
/// A guardian is a person, linked to one or more of the school's students:
/// [children] says how many, so the office knows an edit here changes what a
/// sibling's record says too.
class GuardianLink {
  const GuardianLink({
    required this.id,
    required this.guardianId,
    required this.name,
    required this.mobile,
    required this.email,
    required this.relationship,
    required this.isPrimary,
    required this.consentAt,
    required this.hasFamilyAccount,
    required this.children,
  });

  factory GuardianLink.fromJson(Map<String, dynamic> json) {
    return GuardianLink(
      id: json['id'] as int,
      guardianId: json['guardian_id'] as int,
      name: json['name'] as String,
      mobile: json['mobile'] as String?,
      email: json['email'] as String?,
      relationship: GuardianRelationship.fromApiValue(json['relationship'] as String?),
      isPrimary: json['is_primary'] as bool,
      consentAt: DateTime.tryParse(json['consent_at'] as String? ?? '')?.toLocal(),
      hasFamilyAccount: json['has_family_account'] as bool,
      children: json['children'] as int,
    );
  }

  /// The link, which is what edits and unlinking address.
  final int id;
  final int guardianId;
  final String name;
  final String? mobile;
  final String? email;
  final GuardianRelationship relationship;
  final bool isPrimary;

  /// When the school noted the guardian's consent to the Family app.
  final DateTime? consentAt;
  final bool hasFamilyAccount;
  final int children;
}

enum GuardianRelationship {
  mother('mother', 'Mother'),
  father('father', 'Father'),
  guardian('guardian', 'Guardian'),
  other('other', 'Other');

  const GuardianRelationship(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static GuardianRelationship fromApiValue(String? value) =>
      values.firstWhere((relationship) => relationship.apiValue == value, orElse: () => guardian);
}

/// A guardian's Family app sign-in, as the office sees it - never a code or
/// passcode, only whether one is set.
class FamilyAccess {
  const FamilyAccess({
    required this.loginMobile,
    required this.consentAt,
    required this.hasAccount,
    required this.hasPasscode,
    required this.isLocked,
    required this.setupCodePending,
    required this.setupCodeExpiresAt,
    required this.devices,
  });

  factory FamilyAccess.fromJson(Map<String, dynamic> json) {
    return FamilyAccess(
      loginMobile: json['login_mobile'] as String?,
      consentAt: DateTime.tryParse(json['consent_at'] as String? ?? '')?.toLocal(),
      hasAccount: json['has_account'] as bool,
      hasPasscode: json['has_passcode'] as bool,
      isLocked: json['is_locked'] as bool,
      setupCodePending: json['setup_code_pending'] as bool,
      setupCodeExpiresAt: DateTime.tryParse(json['setup_code_expires_at'] as String? ?? '')?.toLocal(),
      devices: [
        for (final device in json['devices'] as List<dynamic>) FamilyPhone.fromJson(device as Map<String, dynamic>),
      ],
    );
  }

  final String? loginMobile;
  final DateTime? consentAt;
  final bool hasAccount;
  final bool hasPasscode;
  final bool isLocked;
  final bool setupCodePending;
  final DateTime? setupCodeExpiresAt;
  final List<FamilyPhone> devices;

  List<FamilyPhone> get activeDevices => devices.where((device) => device.revokedAt == null).toList();
}

class FamilyPhone {
  const FamilyPhone({required this.id, required this.name, required this.lastUsedAt, required this.revokedAt});

  factory FamilyPhone.fromJson(Map<String, dynamic> json) {
    return FamilyPhone(
      id: json['id'] as int,
      name: json['name'] as String,
      lastUsedAt: DateTime.tryParse(json['last_used_at'] as String? ?? '')?.toLocal(),
      revokedAt: DateTime.tryParse(json['revoked_at'] as String? ?? '')?.toLocal(),
    );
  }

  final int id;
  final String name;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;
}

/// A setup code just issued: shown once, then never again.
class IssuedSetupCode {
  const IssuedSetupCode({required this.code, required this.expiresAt, required this.loginMobile});

  factory IssuedSetupCode.fromJson(Map<String, dynamic> json) {
    return IssuedSetupCode(
      code: json['setup_code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      loginMobile: json['login_mobile'] as String,
    );
  }

  final String code;
  final DateTime expiresAt;
  final String loginMobile;
}
