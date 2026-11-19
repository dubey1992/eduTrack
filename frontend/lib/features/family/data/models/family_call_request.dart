/// A parent's "please call me" (docs/parent-student-app.md, F5).
class FamilyCallRequest {
  const FamilyCallRequest({
    required this.id,
    required this.toOffice,
    required this.reason,
    required this.called,
    required this.sentAt,
    this.preferredTime,
    this.calledBy,
    this.calledAt,
  });

  factory FamilyCallRequest.fromJson(Map<String, dynamic> json) => FamilyCallRequest(
    id: json['id'] as int,
    toOffice: json['recipient'] == 'office',
    reason: json['reason'] as String,
    preferredTime: json['preferred_time'] as String?,
    called: json['status'] == 'called',
    sentAt: DateTime.parse(json['sent_at'] as String).toLocal(),
    calledBy: json['called_by'] as String?,
    calledAt: json['called_at'] == null ? null : DateTime.parse(json['called_at'] as String).toLocal(),
  );

  final int id;

  /// To the school office; otherwise to the class teacher.
  final bool toOffice;
  final String reason;
  final String? preferredTime;

  /// The school has called back.
  final bool called;
  final DateTime sentAt;

  /// Who rang back, and when (4.2).
  final String? calledBy;
  final DateTime? calledAt;
}
