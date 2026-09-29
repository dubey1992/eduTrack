/// What would happen if a class were promoted into the next year
/// (docs/promotion.md).
///
/// Nothing here has been written: this is the list an administrator reads,
/// edits per student, and only then runs. The defaults come from the server
/// so that the run applies the same rules the screen showed.
library;

/// What the administrator asks for one student. Past tense - promoted,
/// retained - is what a run records; this is the instruction.
enum PromotionOutcome {
  promote('promote', 'Promote', 'Moves up to the next class'),
  retain('retain', 'Retain', 'Repeats the year in the same class'),
  graduate('graduate', 'Graduate', 'Finishes school'),
  leave('leave', 'Left out', 'Has already left the school');

  const PromotionOutcome(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;
  final String description;

  static PromotionOutcome fromApiValue(String value) =>
      PromotionOutcome.values.firstWhere((o) => o.apiValue == value, orElse: () => PromotionOutcome.promote);
}

/// One side of the move: a section in a year.
class PromotionSide {
  const PromotionSide({
    required this.academicYearId,
    required this.academicYearName,
    required this.classSectionId,
    required this.classSectionName,
    required this.schoolClassId,
    required this.schoolClassName,
    this.isSuggested = false,
  });

  factory PromotionSide.fromJson(Map<String, dynamic> json) {
    return PromotionSide(
      academicYearId: json['academic_year_id'] as int,
      academicYearName: json['academic_year_name'] as String? ?? '',
      classSectionId: json['class_section_id'] as int?,
      classSectionName: json['class_section_name'] as String?,
      schoolClassId: json['school_class_id'] as int?,
      schoolClassName: json['school_class_name'] as String?,
      isSuggested: json['is_suggested'] as bool? ?? false,
    );
  }

  final int academicYearId;
  final String academicYearName;
  final int? classSectionId;
  final String? classSectionName;
  final int? schoolClassId;
  final String? schoolClassName;

  /// True when the backend guessed the target rather than the school naming
  /// it, which the screen says out loud.
  final bool isSuggested;
}

/// The marks the suggestions were read from, and the mark they were read
/// against.
class PromotionSuggestions {
  const PromotionSuggestions({required this.available, this.termName, this.passPercentage});

  factory PromotionSuggestions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PromotionSuggestions(available: false);

    return PromotionSuggestions(
      available: json['available'] as bool? ?? false,
      termName: json['term_name'] as String?,
      passPercentage: json['pass_percentage'] as String?,
    );
  }

  final bool available;
  final String? termName;
  final String? passPercentage;
}

/// One student's row in the preview.
class PromotionStudent {
  const PromotionStudent({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.rollNumber,
    required this.status,
    required this.defaultOutcome,
    required this.isBlocked,
    this.blockedReason,
    this.averagePercentage,
    this.attendancePercentage,
    this.suggestedOutcome,
    this.suggestionReason,
  });

  factory PromotionStudent.fromJson(Map<String, dynamic> json) {
    final suggested = json['suggested_outcome'] as String?;

    return PromotionStudent(
      studentId: json['student_id'] as int,
      name: json['name'] as String? ?? '',
      admissionNumber: json['admission_number'] as String? ?? '',
      rollNumber: json['roll_number'] as String?,
      status: json['status'] as String? ?? 'active',
      defaultOutcome: PromotionOutcome.fromApiValue(json['default_outcome'] as String? ?? 'promote'),
      isBlocked: json['is_blocked'] as bool? ?? false,
      blockedReason: json['blocked_reason'] as String?,
      averagePercentage: json['average_percentage'] as String?,
      attendancePercentage: (json['attendance_percentage'] as num?)?.toDouble(),
      suggestedOutcome: suggested == null ? null : PromotionOutcome.fromApiValue(suggested),
      suggestionReason: json['suggestion_reason'] as String?,
    );
  }

  final int studentId;
  final String name;
  final String admissionNumber;
  final String? rollNumber;
  final String status;
  final PromotionOutcome defaultOutcome;

  /// Already has a place in the target year. Listed rather than dropped - a
  /// roster that quietly omits a child is how a child is left behind - but
  /// nothing can be asked for them.
  final bool isBlocked;
  final String? blockedReason;

  final String? averagePercentage;
  final double? attendancePercentage;

  /// Only ever [PromotionOutcome.retain], and only ever a suggestion: the
  /// default is untouched by it.
  final PromotionOutcome? suggestedOutcome;
  final String? suggestionReason;
}

class PromotionPreview {
  const PromotionPreview({
    required this.from,
    required this.to,
    required this.isGraduating,
    required this.canRun,
    required this.students,
    required this.suggestions,
    this.cannotRunReason,
  });

  factory PromotionPreview.fromJson(Map<String, dynamic> json) {
    return PromotionPreview(
      from: PromotionSide.fromJson(json['from'] as Map<String, dynamic>),
      to: PromotionSide.fromJson(json['to'] as Map<String, dynamic>),
      isGraduating: json['is_graduating'] as bool? ?? false,
      canRun: json['can_run'] as bool? ?? false,
      cannotRunReason: json['cannot_run_reason'] as String?,
      suggestions: PromotionSuggestions.fromJson(json['suggestions'] as Map<String, dynamic>?),
      students: [
        for (final row in (json['students'] as List<dynamic>? ?? const []))
          PromotionStudent.fromJson(row as Map<String, dynamic>),
      ],
    );
  }

  final PromotionSide from;
  final PromotionSide to;

  /// The source class has nothing above it, so the year ends here.
  final bool isGraduating;

  final bool canRun;

  /// Why not, when [canRun] is false - today only NOTHING_TO_PROMOTE.
  final String? cannotRunReason;

  final PromotionSuggestions suggestions;
  final List<PromotionStudent> students;
}
