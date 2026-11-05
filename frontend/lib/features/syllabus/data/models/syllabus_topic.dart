/// One entry in a subject's curriculum outline (e.g. "Chapter 3: Fractions"),
/// in the order it should be taught. See `SyllabusChecklistItem` for how a
/// specific class section's coverage of this topic is tracked separately.
class SyllabusTopic {
  const SyllabusTopic({
    required this.id,
    required this.schoolId,
    required this.subjectId,
    required this.subjectName,
    required this.title,
    required this.sequenceNumber,
    this.classLevel,
    this.classLevelName,
  });

  factory SyllabusTopic.fromJson(Map<String, dynamic> json) {
    return SyllabusTopic(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      subjectId: json['subject_id'] as int,
      subjectName: json['subject_name'] as String?,
      title: json['title'] as String,
      sequenceNumber: json['sequence_number'] as int,
      classLevel: json['class_level'] as int?,
      classLevelName: json['class_level_name'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final int subjectId;
  final String? subjectName;
  final String title;
  final int sequenceNumber;

  /// The class the topic is for - Playgroup -3 to Class 12 - shared by every
  /// section of it (decided 2026-11-05). Null: written before topics had
  /// classes, so it still applies to every class.
  final int? classLevel;

  /// "Class 5", or "All classes" for a topic with no class.
  final String? classLevelName;

  bool get isForEveryClass => classLevel == null;
}
