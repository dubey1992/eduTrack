/// One named, dated slice of an academic year (docs/assessments.md).
///
/// A term is what a result is filed under, so it always belongs to a year and
/// carries its own order within it - "Term 1" before "Term 2", whatever the
/// dates say.
class AcademicTerm {
  const AcademicTerm({
    required this.id,
    required this.schoolId,
    required this.academicYearId,
    required this.academicYearName,
    required this.name,
    required this.sequenceNumber,
    required this.startDate,
    required this.endDate,
  });

  factory AcademicTerm.fromJson(Map<String, dynamic> json) {
    return AcademicTerm(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      academicYearId: json['academic_year_id'] as int,
      academicYearName: json['academic_year_name'] as String?,
      name: json['name'] as String,
      sequenceNumber: json['sequence_number'] as int,
      // Dates, not instants: parsed as written, never shifted by a timezone.
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
    );
  }

  final int id;
  final int schoolId;
  final int academicYearId;
  final String? academicYearName;
  final String name;
  final int sequenceNumber;
  final DateTime startDate;
  final DateTime endDate;
}
