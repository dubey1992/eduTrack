/// One academic year of a student's history (docs/promotion.md).
///
/// The class name travels with the row because a section that was later
/// renamed or removed should still read as the class it was.
class StudentEnrollment {
  const StudentEnrollment({
    required this.id,
    required this.academicYearId,
    required this.academicYearName,
    required this.className,
    required this.sectionName,
    required this.rollNumber,
    required this.status,
  });

  factory StudentEnrollment.fromJson(Map<String, dynamic> json) {
    return StudentEnrollment(
      id: json['id'] as int,
      academicYearId: json['academic_year_id'] as int,
      academicYearName: json['academic_year_name'] as String,
      className: json['class_name'] as String,
      sectionName: json['section_name'] as String?,
      rollNumber: json['roll_number'] as String?,
      status: EnrollmentStatus.fromApiValue(json['status'] as String),
    );
  }

  final int id;
  final int academicYearId;
  final String academicYearName;
  final String className;

  /// Null once the section itself has been removed; the class remains.
  final String? sectionName;
  final String? rollNumber;
  final EnrollmentStatus status;

  /// "Grade 7 A", or just "Grade 7" when the section is gone.
  String get classLabel => sectionName == null ? className : '$className $sectionName';
}

/// How a year ended. Only [studying] is written today; the rest are what a
/// promotion will record.
enum EnrollmentStatus {
  studying('studying', 'Studying'),
  promoted('promoted', 'Promoted'),
  retained('retained', 'Repeated the year'),
  graduated('graduated', 'Graduated'),
  left('left', 'Left');

  const EnrollmentStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static EnrollmentStatus fromApiValue(String value) {
    return values.firstWhere((status) => status.apiValue == value, orElse: () => EnrollmentStatus.studying);
  }
}
