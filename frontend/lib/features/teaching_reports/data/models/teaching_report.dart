/// One daily teaching report, as returned by `POST /teaching-reports`,
/// `GET /teaching-reports`, and `PATCH /teaching-reports/{id}/review`.
class TeachingReport {
  const TeachingReport({
    required this.id,
    required this.schoolId,
    required this.timetableEntryId,
    required this.classSectionName,
    required this.periodNumber,
    required this.subjectName,
    required this.teacherId,
    required this.teacherName,
    required this.reportDate,
    required this.topicTaught,
    required this.homework,
    required this.remarks,
    required this.reviewedBy,
    required this.reviewedByName,
    required this.reviewedAt,
  });

  factory TeachingReport.fromJson(Map<String, dynamic> json) {
    return TeachingReport(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      timetableEntryId: json['timetable_entry_id'] as int,
      classSectionName: json['class_section_name'] as String?,
      periodNumber: json['period_number'] as int?,
      subjectName: json['subject_name'] as String?,
      teacherId: json['teacher_id'] as int,
      teacherName: json['teacher_name'] as String?,
      reportDate: json['report_date'] as String,
      topicTaught: json['topic_taught'] as String,
      homework: json['homework'] as String?,
      remarks: json['remarks'] as String?,
      reviewedBy: json['reviewed_by'] as int?,
      reviewedByName: json['reviewed_by_name'] as String?,
      reviewedAt: json['reviewed_at'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final int timetableEntryId;
  final String? classSectionName;
  final int? periodNumber;
  final String? subjectName;
  final int teacherId;
  final String? teacherName;

  /// yyyy-MM-dd.
  final String reportDate;
  final String topicTaught;
  final String? homework;
  final String? remarks;
  final int? reviewedBy;
  final String? reviewedByName;
  final String? reviewedAt;

  bool get isReviewed => reviewedBy != null;
}
