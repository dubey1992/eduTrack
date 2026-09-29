/// A promotion that has already happened (docs/promotion.md).
///
/// The counts are the batch's own, stored when it ran: a figure worked out
/// again now would drift the moment somebody moves a child by hand
/// afterwards, which is exactly the correction the product expects.
library;

class PromotionBatch {
  const PromotionBatch({
    required this.id,
    required this.fromAcademicYearName,
    required this.toAcademicYearName,
    required this.fromClassSectionName,
    required this.toClassSectionName,
    required this.promotedCount,
    required this.retainedCount,
    required this.graduatedCount,
    required this.leftCount,
    required this.studentCount,
    required this.runByName,
    required this.runAt,
    this.students = const [],
  });

  factory PromotionBatch.fromJson(Map<String, dynamic> json) {
    return PromotionBatch(
      id: json['id'] as int,
      fromAcademicYearName: json['from_academic_year_name'] as String? ?? '',
      toAcademicYearName: json['to_academic_year_name'] as String? ?? '',
      fromClassSectionName: json['from_class_section_name'] as String? ?? '',
      // Null when every student graduated: there was nowhere to land.
      toClassSectionName: json['to_class_section_name'] as String?,
      promotedCount: json['promoted_count'] as int? ?? 0,
      retainedCount: json['retained_count'] as int? ?? 0,
      graduatedCount: json['graduated_count'] as int? ?? 0,
      leftCount: json['left_count'] as int? ?? 0,
      studentCount: json['student_count'] as int? ?? 0,
      runByName: json['run_by_name'] as String? ?? '',
      runAt: json['run_at'] == null ? null : DateTime.tryParse(json['run_at'] as String),
      students: [
        for (final row in (json['students'] as List<dynamic>? ?? const []))
          PromotionBatchStudent.fromJson(row as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final String fromAcademicYearName;
  final String toAcademicYearName;
  final String fromClassSectionName;
  final String? toClassSectionName;
  final int promotedCount;
  final int retainedCount;
  final int graduatedCount;
  final int leftCount;
  final int studentCount;
  final String runByName;
  final DateTime? runAt;

  /// Only on a batch read one at a time; the list leaves them out.
  final List<PromotionBatchStudent> students;
}

/// What one run did to one student. Past tense, because it is the record:
/// promoted, retained, graduated, left.
class PromotionBatchStudent {
  const PromotionBatchStudent({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.rollNumber,
    required this.fromClassName,
    required this.fromSectionName,
    required this.outcome,
    required this.toClassName,
    required this.toSectionName,
  });

  factory PromotionBatchStudent.fromJson(Map<String, dynamic> json) {
    return PromotionBatchStudent(
      studentId: json['student_id'] as int,
      name: json['name'] as String? ?? '',
      admissionNumber: json['admission_number'] as String? ?? '',
      rollNumber: json['roll_number'] as String?,
      fromClassName: json['from_class_name'] as String? ?? '',
      fromSectionName: json['from_section_name'] as String?,
      outcome: json['outcome'] as String? ?? '',
      toClassName: json['to_class_name'] as String?,
      toSectionName: json['to_section_name'] as String?,
    );
  }

  final int studentId;
  final String name;
  final String admissionNumber;
  final String? rollNumber;
  final String fromClassName;
  final String? fromSectionName;
  final String outcome;

  /// Where they went - absent for the two outcomes where nobody went
  /// anywhere.
  final String? toClassName;
  final String? toSectionName;

  String get outcomeLabel =>
      const {'promoted': 'Promoted', 'retained': 'Retained', 'graduated': 'Graduated', 'left': 'Left out'}[outcome] ??
      outcome;

  String get destination {
    if (toClassName == null) return '-';

    return '$toClassName ${toSectionName ?? ''}'.trim();
  }
}
