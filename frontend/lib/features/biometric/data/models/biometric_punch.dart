import '../../../../core/network/paginated_response.dart';

/// One punch a device recorded (docs/biometric.md, B2).
class BiometricPunch {
  const BiometricPunch({
    required this.id,
    required this.schoolId,
    required this.biometricUserId,
    required this.staffProfileId,
    required this.staffName,
    required this.employeeId,
    required this.deviceName,
    required this.source,
    required this.punchedAtLabel,
    required this.localDate,
  });

  factory BiometricPunch.fromJson(Map<String, dynamic> json) {
    return BiometricPunch(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      biometricUserId: json['biometric_user_id'] as String,
      staffProfileId: json['staff_profile_id'] as int?,
      staffName: json['staff_name'] as String?,
      employeeId: json['employee_id'] as String?,
      deviceName: json['device_name'] as String?,
      source: json['source'] as String? ?? 'upload',
      punchedAtLabel: json['punched_at_label'] as String? ?? '',
      localDate: json['local_date'] as String,
    );
  }

  final int id;
  final int schoolId;

  /// The id the device knows this person by.
  final String biometricUserId;

  /// Null when nobody has mapped that id to a person yet. The screen says so
  /// rather than leaving a blank: an unattributed punch is work for
  /// somebody, not an absence of information.
  final int? staffProfileId;
  final String? staffName;
  final String? employeeId;

  final String? deviceName;
  final String source;

  /// On the school's own clock. 09:02 in Muscat is not 09:02 anywhere else,
  /// and the person reading this is at the school.
  final String punchedAtLabel;
  final String localDate;

  bool get isUnattributed => staffProfileId == null;
}

/// What became of an uploaded file.
class PunchUploadResult {
  const PunchUploadResult({
    required this.read,
    required this.accepted,
    required this.duplicate,
    required this.refused,
    this.registerFilled = 0,
    this.registerMarked = 0,
  });

  factory PunchUploadResult.fromJson(Map<String, dynamic> json) {
    return PunchUploadResult(
      read: json['read'] as int? ?? 0,
      accepted: json['accepted'] as int? ?? 0,
      duplicate: json['duplicate'] as int? ?? 0,
      refused: ((json['refused'] as List?) ?? const []).map((line) => '$line').toList(),
      registerFilled: json['register_filled'] as int? ?? 0,
      registerMarked: json['register_marked'] as int? ?? 0,
    );
  }

  final int read;

  /// New punches. The rest were already in.
  final int accepted;

  /// Already seen. Not an error: devices resend and exports overlap.
  final int duplicate;

  /// Lines that did not become a punch, each saying which line and why.
  final List<String> refused;

  /// Register rows whose check-in and check-out these punches filled in
  /// (docs/biometric.md, B3). Zero with punches accepted usually means
  /// nobody has been enrolled on the device yet, which is worth saying.
  final int registerFilled;

  /// Days nobody had marked that these punches marked Present
  /// (docs/biometric.md, B5).
  final int registerMarked;

  bool get hasProblems => refused.isNotEmpty;
}

/// A page of the log, plus the one number that does not come from the page.
///
/// "None on this page" and "none at all" are different answers about the
/// punches nobody can attribute, and twenty rows cannot tell them apart - so
/// the server counts them under the same filters and sends the total along.
class PunchPage {
  const PunchPage({required this.page, required this.unmatchedTotal});

  factory PunchPage.fromJson(Map<String, dynamic> json) {
    return PunchPage(
      page: PaginatedResponse.fromJson(json, BiometricPunch.fromJson),
      unmatchedTotal: json['unmatched_total'] as int? ?? 0,
    );
  }

  final PaginatedResponse<BiometricPunch> page;
  final int unmatchedTotal;
}
