/// One topic's completion status for a specific class section, as returned
/// inline within a `SyllabusChecklist` - a row's completion is a fact about
/// "this section, this topic", not about the topic in general (two
/// sections of the same subject can be at different points in the outline).
class SyllabusChecklistItem {
  const SyllabusChecklistItem({
    required this.id,
    required this.title,
    required this.sequenceNumber,
    required this.completed,
    required this.completedByName,
    required this.completedAt,
  });

  factory SyllabusChecklistItem.fromJson(Map<String, dynamic> json) {
    return SyllabusChecklistItem(
      id: json['id'] as int,
      title: json['title'] as String,
      sequenceNumber: json['sequence_number'] as int,
      completed: json['completed'] as bool,
      completedByName: json['completed_by_name'] as String?,
      completedAt: json['completed_at'] as String?,
    );
  }

  final int id;
  final String title;
  final int sequenceNumber;
  final bool completed;
  final String? completedByName;
  final String? completedAt;
}

/// A subject's full outline, each topic paired with one class section's
/// completion mark - as returned by `GET /syllabus-progress`. The
/// prototype's "Syllabus 68%" style figure is `progressPercent` here.
class SyllabusChecklist {
  const SyllabusChecklist({
    required this.subjectId,
    required this.subjectName,
    required this.classSectionId,
    required this.totalTopics,
    required this.completedTopics,
    required this.progressPercent,
    required this.topics,
  });

  factory SyllabusChecklist.fromJson(Map<String, dynamic> json) {
    return SyllabusChecklist(
      subjectId: json['subject_id'] as int,
      subjectName: json['subject_name'] as String,
      classSectionId: json['class_section_id'] as int,
      totalTopics: json['total_topics'] as int,
      completedTopics: json['completed_topics'] as int,
      progressPercent: json['progress_percent'] as int,
      topics: (json['topics'] as List).cast<Map<String, dynamic>>().map(SyllabusChecklistItem.fromJson).toList(),
    );
  }

  final int subjectId;
  final String subjectName;
  final int classSectionId;
  final int totalTopics;
  final int completedTopics;
  final int progressPercent;
  final List<SyllabusChecklistItem> topics;
}
