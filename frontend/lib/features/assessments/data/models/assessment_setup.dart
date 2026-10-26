/// What a teacher chooses from when setting a test on the phone -
/// `GET /assessments/setup` (docs/teacher-app.md, T5).
class AssessmentSetup {
  const AssessmentSetup({
    required this.classes,
    required this.terms,
    required this.gradeScales,
    required this.passPercentage,
  });

  factory AssessmentSetup.fromJson(Map<String, dynamic> json) => AssessmentSetup(
    classes: [for (final row in json['classes'] as List) TaughtClass.fromJson(row as Map<String, dynamic>)],
    terms: [for (final row in json['terms'] as List) SetupTerm.fromJson(row as Map<String, dynamic>)],
    gradeScales: [
      for (final row in json['grade_scales'] as List) SetupGradeScale.fromJson(row as Map<String, dynamic>),
    ],
    passPercentage: json['pass_percentage'] as int?,
  );

  /// The classes and subjects the teacher is timetabled for this year.
  final List<TaughtClass> classes;

  /// This year's terms, in order.
  final List<SetupTerm> terms;
  final List<SetupGradeScale> gradeScales;

  /// Used when a test sets no pass mark of its own.
  final int? passPercentage;

  /// The term a date falls in - a test belongs to the term it is sat in.
  SetupTerm? termFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    for (final term in terms) {
      if (!day.isBefore(term.startDate) && !day.isAfter(term.endDate)) return term;
    }
    return null;
  }

  SetupGradeScale? get defaultScale {
    for (final scale in gradeScales) {
      if (scale.isDefault) return scale;
    }
    return gradeScales.isEmpty ? null : gradeScales.first;
  }
}

class TaughtClass {
  const TaughtClass({
    required this.classSectionId,
    required this.classSection,
    required this.subjectId,
    required this.subjectName,
  });

  factory TaughtClass.fromJson(Map<String, dynamic> json) => TaughtClass(
    classSectionId: json['class_section_id'] as int,
    classSection: json['class_section'] as String,
    subjectId: json['subject_id'] as int,
    subjectName: json['subject_name'] as String,
  );

  final int classSectionId;
  final String classSection;
  final int subjectId;
  final String subjectName;

  String get label => '$subjectName · $classSection';
}

class SetupTerm {
  const SetupTerm({required this.id, required this.name, required this.startDate, required this.endDate});

  factory SetupTerm.fromJson(Map<String, dynamic> json) => SetupTerm(
    id: json['id'] as int,
    name: json['name'] as String,
    startDate: DateTime.parse(json['start_date'] as String),
    endDate: DateTime.parse(json['end_date'] as String),
  );

  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
}

class SetupGradeScale {
  const SetupGradeScale({required this.id, required this.name, required this.isDefault});

  factory SetupGradeScale.fromJson(Map<String, dynamic> json) =>
      SetupGradeScale(id: json['id'] as int, name: json['name'] as String, isDefault: json['is_default'] as bool);

  final int id;
  final String name;
  final bool isDefault;
}
