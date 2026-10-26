/// One class and subject the signed-in teacher teaches this year, with how
/// far its syllabus has got - `GET /syllabus-progress/mine`
/// (docs/teacher-app.md, T3).
class MySyllabusClass {
  const MySyllabusClass({
    required this.classSectionId,
    required this.classSection,
    required this.subjectId,
    required this.subjectName,
    required this.totalTopics,
    required this.completedTopics,
    required this.progressPercent,
  });

  factory MySyllabusClass.fromJson(Map<String, dynamic> json) => MySyllabusClass(
    classSectionId: json['class_section_id'] as int,
    classSection: json['class_section'] as String,
    subjectId: json['subject_id'] as int,
    subjectName: json['subject_name'] as String,
    totalTopics: json['total_topics'] as int,
    completedTopics: json['completed_topics'] as int,
    progressPercent: json['progress_percent'] as int,
  );

  final int classSectionId;

  /// "Grade 3 A".
  final String classSection;
  final int subjectId;
  final String subjectName;
  final int totalTopics;
  final int completedTopics;
  final int progressPercent;
}
