/// Where a signup request has got to. Mirrors the backend's
/// App\Enums\EarlyAccessStatus.
enum EarlyAccessStatus {
  newRequest('new', 'New'),
  contacted('contacted', 'Contacted'),
  converted('converted', 'Converted'),
  declined('declined', 'Declined');

  const EarlyAccessStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static EarlyAccessStatus fromApiValue(String value) =>
      EarlyAccessStatus.values.firstWhere((s) => s.apiValue == value, orElse: () => EarlyAccessStatus.newRequest);

  /// The statuses somebody may choose. Converted is set by onboarding the
  /// school, never by hand - see the backend enum for why.
  static List<EarlyAccessStatus> get settable => [newRequest, contacted, declined];

  /// Still somebody's to deal with.
  bool get isOpen => this == newRequest || this == contacted;
}

/// A school asking to be let in.
class EarlyAccessRequest {
  const EarlyAccessRequest({
    required this.id,
    required this.schoolName,
    required this.contactName,
    this.contactRole,
    required this.email,
    required this.phone,
    required this.city,
    required this.country,
    this.expectedStudents,
    this.currentSoftware,
    this.message,
    required this.status,
    this.notes,
    this.convertedSchoolId,
    this.convertedSchoolName,
    this.reviewedByName,
    this.reviewedAt,
    required this.submittedAt,
  });

  factory EarlyAccessRequest.fromJson(Map<String, dynamic> json) {
    return EarlyAccessRequest(
      id: json['id'] as int,
      schoolName: json['school_name'] as String,
      contactName: json['contact_name'] as String,
      contactRole: json['contact_role'] as String?,
      email: json['email'] as String,
      phone: json['phone'] as String,
      city: json['city'] as String,
      country: json['country'] as String,
      expectedStudents: json['expected_students'] as int?,
      currentSoftware: json['current_software'] as String?,
      message: json['message'] as String?,
      status: EarlyAccessStatus.fromApiValue(json['status'] as String),
      notes: json['notes'] as String?,
      convertedSchoolId: json['converted_school_id'] as int?,
      convertedSchoolName: json['converted_school_name'] as String?,
      reviewedByName: json['reviewed_by_name'] as String?,
      reviewedAt: json['reviewed_at'] as String?,
      submittedAt: json['submitted_at'] as String? ?? '',
    );
  }

  final int id;
  final String schoolName;
  final String contactName;
  final String? contactRole;
  final String email;
  final String phone;
  final String city;
  final String country;
  final int? expectedStudents;
  final String? currentSoftware;
  final String? message;
  final EarlyAccessStatus status;
  final String? notes;
  final int? convertedSchoolId;
  final String? convertedSchoolName;
  final String? reviewedByName;
  final String? reviewedAt;
  final String submittedAt;

  String get location => '$city, $country';
}
