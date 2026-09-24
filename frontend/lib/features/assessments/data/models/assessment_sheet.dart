import 'assessment.dart';

/// The marks sheet for one class test: the test, and a row per student of
/// the class (docs/assessments.md).
class AssessmentSheet {
  const AssessmentSheet({required this.assessment, required this.entries});

  factory AssessmentSheet.fromJson(Map<String, dynamic> json) {
    return AssessmentSheet(
      assessment: Assessment.fromJson(json['assessment'] as Map<String, dynamic>),
      entries: [for (final row in json['entries'] as List<dynamic>) SheetEntry.fromJson(row as Map<String, dynamic>)],
    );
  }

  final Assessment assessment;
  final List<SheetEntry> entries;

  /// How many of the class have been marked one way or the other. A teacher
  /// wants to know what is left, not what is done.
  int get markedCount => entries.where((entry) => entry.isMarked).length;

  bool get isComplete => entries.isNotEmpty && markedCount == entries.length;
}

/// One student's line on the sheet.
///
/// A mark and an absence are different facts, which is why they are separate
/// fields: an absentee has no mark at all, and later leaves the average's
/// denominator rather than dragging it down.
class SheetEntry {
  const SheetEntry({
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.rollNumber,
    required this.marksObtained,
    required this.isAbsent,
    required this.grade,
    required this.percentage,
    required this.passed,
    required this.remarks,
  });

  factory SheetEntry.fromJson(Map<String, dynamic> json) {
    return SheetEntry(
      studentId: json['student_id'] as int,
      studentName: json['student_name'] as String,
      admissionNumber: json['admission_number'] as String,
      rollNumber: json['roll_number'] as String?,
      marksObtained: json['marks_obtained'] as String?,
      isAbsent: json['is_absent'] as bool,
      grade: json['grade'] as String?,
      percentage: json['percentage'] as String?,
      passed: json['passed'] as bool?,
      remarks: json['remarks'] as String?,
    );
  }

  final int studentId;
  final String studentName;
  final String admissionNumber;
  final String? rollNumber;
  final String? marksObtained;
  final bool isAbsent;
  final String? grade;
  final String? percentage;

  /// Null where the question does not arise: nobody marked yet, or absent.
  final bool? passed;
  final String? remarks;

  /// Marked either way. A blank is not a zero: it means nobody has said yet.
  bool get isMarked => isAbsent || (marksObtained != null && marksObtained!.isNotEmpty);

  /// "17.5", not "17.50", for a box somebody has to read and retype.
  String get marksForEditing => Assessment.tidyMarks(marksObtained) ?? '';

  SheetEntry copyWith({String? marksObtained, bool? isAbsent, bool clearMarks = false}) {
    return SheetEntry(
      studentId: studentId,
      studentName: studentName,
      admissionNumber: admissionNumber,
      rollNumber: rollNumber,
      marksObtained: clearMarks ? null : (marksObtained ?? this.marksObtained),
      isAbsent: isAbsent ?? this.isAbsent,
      grade: grade,
      percentage: percentage,
      passed: passed,
      remarks: remarks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'marks_obtained': isAbsent ? null : marksObtained,
      'is_absent': isAbsent,
      'remarks': remarks,
    };
  }
}

/// What a marks file would save, before it saves it (docs/assessments.md).
///
/// Named rather than tabular: a marks file is read as "did this land against
/// the right children", so each row carries the admission number it matched.
class MarksPreview {
  const MarksPreview({required this.rowCount, required this.rows});

  factory MarksPreview.fromJson(Map<String, dynamic> json) {
    return MarksPreview(
      rowCount: json['row_count'] as int? ?? 0,
      rows: [
        for (final row in json['rows'] as List? ?? const [])
          MarksPreviewRow.fromJson((row as Map).cast<String, dynamic>()),
      ],
    );
  }

  final int rowCount;
  final List<MarksPreviewRow> rows;
}

class MarksPreviewRow {
  const MarksPreviewRow({
    required this.studentId,
    required this.admissionNumber,
    required this.marksObtained,
    required this.isAbsent,
  });

  factory MarksPreviewRow.fromJson(Map<String, dynamic> json) {
    return MarksPreviewRow(
      studentId: json['student_id'] as int,
      admissionNumber: json['admission_number'] as String?,
      marksObtained: json['marks_obtained'] as String?,
      isAbsent: json['is_absent'] as bool? ?? false,
    );
  }

  final int studentId;
  final String? admissionNumber;
  final String? marksObtained;
  final bool isAbsent;

  /// "17.5", or "Absent", or a dash for a row that clears a mark.
  String get readsAs {
    if (isAbsent) return 'Absent';

    final marks = marksObtained;

    return marks == null ? '-' : (Assessment.tidyMarks(marks) ?? marks);
  }
}
