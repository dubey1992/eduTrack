/// The prototype's audience picker.
enum AnnouncementAudience {
  allSchool('all_school', 'All School'),
  teachers('teachers', 'Teachers'),
  parents('parents', 'Parents'),
  classSection('class_section', 'A class section'),
  department('department', 'A department');

  const AnnouncementAudience(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Audiences that name one class or one department.
  bool get needsTarget => this == AnnouncementAudience.classSection || this == AnnouncementAudience.department;

  /// Guardians have no login, so these can never be reached in-app.
  bool get reachesStaff =>
      this == AnnouncementAudience.allSchool ||
      this == AnnouncementAudience.teachers ||
      this == AnnouncementAudience.department;

  static AnnouncementAudience fromApiValue(String value) =>
      AnnouncementAudience.values.firstWhere((a) => a.apiValue == value, orElse: () => AnnouncementAudience.allSchool);
}

/// The prototype's channel picker.
enum AnnouncementChannels {
  smsAndInApp('sms_in_app', 'SMS + In-app'),
  smsOnly('sms', 'SMS Only'),
  inAppOnly('in_app', 'In-app Only');

  const AnnouncementChannels(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AnnouncementChannels fromApiValue(String value) => AnnouncementChannels.values.firstWhere(
    (c) => c.apiValue == value,
    orElse: () => AnnouncementChannels.smsAndInApp,
  );
}

/// A published notice, with what it cost to send.
class Announcement {
  const Announcement({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.title,
    required this.body,
    required this.audienceType,
    required this.audienceId,
    required this.audienceLabel,
    required this.channels,
    required this.expiresAt,
    required this.hasExpired,
    required this.publishedByName,
    required this.publishedAt,
    required this.recipientsCount,
    required this.smsCount,
    required this.inAppCount,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      title: json['title'] as String,
      body: json['body'] as String,
      audienceType: AnnouncementAudience.fromApiValue(json['audience_type'] as String),
      audienceId: json['audience_id'] as int?,
      audienceLabel: json['audience_label'] as String,
      channels: AnnouncementChannels.fromApiValue(json['channels'] as String),
      expiresAt: json['expires_at'] as String?,
      hasExpired: json['has_expired'] as bool? ?? false,
      publishedByName: json['published_by_name'] as String?,
      publishedAt: json['published_at'] as String?,
      recipientsCount: json['recipients_count'] as int? ?? 0,
      smsCount: json['sms_count'] as int? ?? 0,
      inAppCount: json['in_app_count'] as int? ?? 0,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String title;
  final String body;
  final AnnouncementAudience audienceType;
  final int? audienceId;
  final String audienceLabel;
  final AnnouncementChannels channels;
  final String? expiresAt;
  final bool hasExpired;
  final String? publishedByName;
  final String? publishedAt;
  final int recipientsCount;
  final int smsCount;
  final int inAppCount;
}

/// How many people an audience would reach, shown before anything is sent.
class AudiencePreview {
  const AudiencePreview({
    required this.recipients,
    required this.sms,
    required this.inApp,
    required this.audienceLabel,
  });

  factory AudiencePreview.fromJson(Map<String, dynamic> json) {
    return AudiencePreview(
      recipients: json['recipients'] as int? ?? 0,
      sms: json['sms'] as int? ?? 0,
      inApp: json['in_app'] as int? ?? 0,
      audienceLabel: json['audience_label'] as String? ?? '',
    );
  }

  final int recipients;
  final int sms;
  final int inApp;
  final String audienceLabel;
}
