import '../../../../core/utils/date_format.dart';

/// Where a demo request stands. Mirrors the backend's DemoRequestStatus.
enum DemoRequestStatus {
  newRequest('new', 'New'),
  scheduled('scheduled', 'Scheduled'),
  done('done', 'Done'),
  declined('declined', 'Declined');

  const DemoRequestStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static DemoRequestStatus fromApiValue(String value) =>
      DemoRequestStatus.values.firstWhere((s) => s.apiValue == value, orElse: () => DemoRequestStatus.newRequest);

  /// Still somebody's to deal with.
  bool get isOpen => this == newRequest || this == scheduled;
}

/// A school asking to be shown the product.
class DemoRequest {
  const DemoRequest({
    required this.id,
    required this.contactName,
    required this.schoolName,
    required this.email,
    required this.phone,
    this.city,
    required this.country,
    this.expectedStudents,
    required this.preferredDate,
    this.preferredTime,
    this.preferredTimeLabel,
    this.timezone,
    this.message,
    required this.status,
    this.notes,
    this.reviewedByName,
    this.reviewedAt,
    required this.submittedAt,
  });

  factory DemoRequest.fromJson(Map<String, dynamic> json) {
    return DemoRequest(
      id: json['id'] as int,
      contactName: json['contact_name'] as String,
      schoolName: json['school_name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      city: json['city'] as String?,
      country: json['country'] as String,
      expectedStudents: json['expected_students'] as int?,
      preferredDate: json['preferred_date'] as String,
      preferredTime: json['preferred_time'] as String?,
      preferredTimeLabel: json['preferred_time_label'] as String?,
      timezone: json['timezone'] as String?,
      message: json['message'] as String?,
      status: DemoRequestStatus.fromApiValue(json['status'] as String),
      notes: json['notes'] as String?,
      reviewedByName: json['reviewed_by_name'] as String?,
      reviewedAt: json['reviewed_at'] as String?,
      submittedAt: json['submitted_at'] as String? ?? '',
    );
  }

  final int id;
  final String contactName;
  final String schoolName;
  final String email;
  final String phone;
  final String? city;
  final String country;
  final int? expectedStudents;

  /// ISO, as the API sends it. Shown through [formatIsoDate].
  final String preferredDate;

  /// morning, afternoon or evening - in the visitor's own [timezone].
  final String? preferredTime;
  final String? preferredTimeLabel;

  /// The visitor's IANA timezone, e.g. Asia/Kolkata.
  final String? timezone;
  final String? message;
  final DemoRequestStatus status;
  final String? notes;
  final String? reviewedByName;
  final String? reviewedAt;
  final String submittedAt;

  String get location => [city, country].nonNulls.join(', ');

  /// The preferred date as a person reads it: 11/05/2026.
  String get preferredDateLabel => formatIsoDate(preferredDate);

  /// Morning · Asia/Kolkata. The part of day means nothing without the
  /// timezone it was picked in, so the two always travel together. Empty when
  /// neither was given.
  String get preferredTimeOfDay => [preferredTimeLabel, timezone].nonNulls.join(' · ');

  /// When they want the demo, as one line: 11/05/2026 · Morning · Asia/Kolkata.
  String get preferredSlot => [preferredDateLabel, preferredTimeLabel, timezone].nonNulls.join(' · ');
}
