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
    this.syllabusTopicName,
    this.status,
    this.reviewNote,
    this.returnedAt,
    this.returnedByName,
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
      syllabusTopicName: json['syllabus_topic_name'] as String?,
      status: json['status'] == null ? null : ReportStatus.fromApiValue(json['status'] as String),
      reviewNote: json['review_note'] as String?,
      returnedAt: json['returned_at'] as String?,
      returnedByName: json['returned_by_name'] as String?,
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

  /// The syllabus topic the report ticked off, if it named one.
  final String? syllabusTopicName;

  /// Awaiting review, sent back to its teacher, or reviewed. Read from the
  /// server where it says; an older answer without it is reviewed or not.
  final ReportStatus? status;

  /// The HOD's note - why it was sent back, or a word with the review.
  final String? reviewNote;
  final String? returnedAt;
  final String? returnedByName;

  bool get isReviewed => reviewedBy != null;

  /// Sent back by the HOD and not yet sent again (docs/teacher-app.md, T7).
  bool get isReturned => !isReviewed && status == ReportStatus.returned;
}

/// Where a report stands with the HOD.
enum ReportStatus {
  awaitingReview('awaiting_review'),
  returned('returned'),
  reviewed('reviewed');

  const ReportStatus(this.apiValue);

  final String apiValue;

  static ReportStatus fromApiValue(String value) =>
      values.firstWhere((status) => status.apiValue == value, orElse: () => ReportStatus.awaitingReview);
}
