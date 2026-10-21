/// A fingerprint reader at a school (docs/biometric.md, B1).
///
/// Staff punch in and out on these; the punches become the check-in and
/// check-out times on the staff register. This is the registry of the
/// hardware itself - no punch is read until B2.
class BiometricDevice {
  const BiometricDevice({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.serialNumber,
    required this.name,
    required this.location,
    required this.status,
    required this.lastSeenAt,
    this.hasPushKey = false,
  });

  factory BiometricDevice.fromJson(Map<String, dynamic> json) {
    return BiometricDevice(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String? ?? '',
      serialNumber: json['serial_number'] as String,
      name: json['name'] as String,
      location: json['location'] as String?,
      status: json['status'] as String,
      lastSeenAt: json['last_seen_at'] as String?,
      hasPushKey: json['has_push_key'] as bool? ?? false,
    );
  }

  final int id;
  final int schoolId;
  final String schoolName;

  /// How the device says who it is. Unique across the platform, because a
  /// box on a school's LAN posts this and nothing more.
  final String serialNumber;

  final String name;
  final String? location;
  final String status;

  /// Null until the device has actually spoken. One registered this morning
  /// and never heard from is a different thing from one that stopped talking
  /// on Tuesday, so the screen says which.
  final String? lastSeenAt;

  /// Whether a shared secret is set, never what it is (docs/biometric.md,
  /// B4). The server does not send the key back: anybody who could read it
  /// could post punches for that school.
  final bool hasPushKey;

  bool get hasNeverSpoken => lastSeenAt == null;
}
