/// A parent's note that their child will be away (docs/parent-student-app.md,
/// F5): sent from the app, then seen by the class teacher.
class FamilyAbsenceNote {
  const FamilyAbsenceNote({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.hasPhoto,
    required this.seen,
    this.seenAt,
  });

  factory FamilyAbsenceNote.fromJson(Map<String, dynamic> json) => FamilyAbsenceNote(
    id: json['id'] as int,
    startDate: DateTime.parse(json['start_date'] as String),
    endDate: DateTime.parse(json['end_date'] as String),
    reason: json['reason'] as String,
    hasPhoto: json['has_photo'] as bool,
    seen: json['status'] == 'acknowledged',
    seenAt: json['acknowledged_at'] == null ? null : DateTime.parse(json['acknowledged_at'] as String).toLocal(),
  );

  final int id;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final bool hasPhoto;

  /// The class teacher has seen it.
  final bool seen;
  final DateTime? seenAt;
}
