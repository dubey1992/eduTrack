/// What a student's marks add up to (docs/assessments.md).
///
/// Every figure is computed by the server and sent as a string, the way
/// money is: a client reading 72.50 as a double would render 72.5 for a
/// figure a school quotes. Null means "nothing to say" - never zero, which
/// on this page is a sentence about a child.
library;

class PerformanceTerm {
  const PerformanceTerm({required this.id, required this.name, required this.sequenceNumber});

  factory PerformanceTerm.fromJson(Map<String, dynamic> json) {
    return PerformanceTerm(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      sequenceNumber: json['sequence_number'] as int? ?? 0,
    );
  }

  final int id;
  final String name;
  final int sequenceNumber;
}

class SubjectPerformance {
  const SubjectPerformance({
    required this.subjectId,
    required this.subjectName,
    required this.assessments,
    required this.absent,
    this.averagePercentage,
    this.grade,
    this.classAveragePercentage,
    this.previousAveragePercentage,
    this.change,
  });

  factory SubjectPerformance.fromJson(Map<String, dynamic> json) {
    return SubjectPerformance(
      subjectId: json['subject_id'] as int,
      subjectName: json['subject_name'] as String? ?? '',
      assessments: json['assessments'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      averagePercentage: json['average_percentage'] as String?,
      grade: json['grade'] as String?,
      classAveragePercentage: json['class_average_percentage'] as String?,
      previousAveragePercentage: json['previous_average_percentage'] as String?,
      change: json['change'] as String?,
    );
  }

  final int subjectId;
  final String subjectName;

  /// How many published tests this term, and how many of them were missed.
  final int assessments;
  final int absent;

  final String? averagePercentage;
  final String? grade;
  final String? classAveragePercentage;
  final String? previousAveragePercentage;

  /// Points gained or lost since the previous term. Null where there is
  /// nothing to compare against.
  final String? change;

  double? get average => averagePercentage == null ? null : double.tryParse(averagePercentage!);
  double? get changeValue => change == null ? null : double.tryParse(change!);

  /// Whether this subject is under the school's own weak mark.
  bool isWeak(num? below) {
    final value = average;

    return below != null && value != null && value < below;
  }
}

/// The term as a whole: every subject's average, evenly, so a subject with
/// eight tests does not drown one with two.
class OverallPerformance {
  const OverallPerformance({
    required this.subjects,
    required this.assessments,
    required this.absent,
    this.averagePercentage,
    this.classAveragePercentage,
    this.previousAveragePercentage,
    this.change,
  });

  factory OverallPerformance.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OverallPerformance(subjects: 0, assessments: 0, absent: 0);

    return OverallPerformance(
      subjects: json['subjects'] as int? ?? 0,
      assessments: json['assessments'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      averagePercentage: json['average_percentage'] as String?,
      classAveragePercentage: json['class_average_percentage'] as String?,
      previousAveragePercentage: json['previous_average_percentage'] as String?,
      change: json['change'] as String?,
    );
  }

  final int subjects;
  final int assessments;
  final int absent;
  final String? averagePercentage;
  final String? classAveragePercentage;
  final String? previousAveragePercentage;
  final String? change;
}

class PerformanceAttendance {
  const PerformanceAttendance({
    required this.workingDays,
    required this.present,
    required this.absent,
    required this.leave,
    required this.notMarked,
    this.attendanceRate,
  });

  factory PerformanceAttendance.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PerformanceAttendance(workingDays: 0, present: 0, absent: 0, leave: 0, notMarked: 0);
    }

    return PerformanceAttendance(
      workingDays: json['working_days'] as int? ?? 0,
      present: json['present'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      leave: json['leave'] as int? ?? 0,
      notMarked: json['not_marked'] as int? ?? 0,
      attendanceRate: (json['attendance_rate'] as num?)?.toDouble(),
    );
  }

  final int workingDays;
  final int present;
  final int absent;
  final int leave;
  final int notMarked;

  /// Null where the period holds no working day at all - a percentage out of
  /// nothing is nothing, not zero.
  final double? attendanceRate;
}

class StudentPerformance {
  const StudentPerformance({
    required this.studentName,
    required this.classSectionName,
    required this.term,
    required this.previousTerm,
    required this.terms,
    required this.subjects,
    required this.overall,
    required this.attendance,
    this.weakBelowPercentage,
  });

  factory StudentPerformance.fromJson(Map<String, dynamic> json) {
    final term = json['term'] as Map<String, dynamic>?;
    final previous = json['previous_term'] as Map<String, dynamic>?;
    final student = (json['student'] as Map<String, dynamic>?) ?? const {};

    return StudentPerformance(
      studentName: student['name'] as String? ?? '',
      classSectionName: student['class_section_name'] as String?,
      term: term == null ? null : PerformanceTerm.fromJson(term),
      previousTerm: previous == null ? null : PerformanceTerm.fromJson(previous),
      terms: [
        for (final row in (json['terms'] as List<dynamic>? ?? const []))
          PerformanceTerm.fromJson(row as Map<String, dynamic>),
      ],
      subjects: [
        for (final row in (json['subjects'] as List<dynamic>? ?? const []))
          SubjectPerformance.fromJson(row as Map<String, dynamic>),
      ],
      overall: OverallPerformance.fromJson(json['overall'] as Map<String, dynamic>?),
      attendance: PerformanceAttendance.fromJson(json['attendance'] as Map<String, dynamic>?),
      weakBelowPercentage: (json['weak_below_percentage'] as num?)?.toDouble(),
    );
  }

  final String studentName;
  final String? classSectionName;

  /// Null for a school with no terms yet - which is a school still being set
  /// up, not an error.
  final PerformanceTerm? term;
  final PerformanceTerm? previousTerm;
  final List<PerformanceTerm> terms;

  final List<SubjectPerformance> subjects;
  final OverallPerformance overall;
  final PerformanceAttendance attendance;

  /// The subject average the school calls weak.
  final double? weakBelowPercentage;

  bool get hasMarks => subjects.isNotEmpty;
}
