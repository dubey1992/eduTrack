/// Academic analytics, A4 (docs/analytics.md): one academic year, term by
/// term, as `GET /analytics/academic` sends it.
///
/// Every figure is the Class Performance report's for that term; a term with
/// no published result is null and is shown as a dash, never as 0%.
library;

class AcademicYearOption {
  const AcademicYearOption({required this.id, required this.name, required this.isCurrent});

  factory AcademicYearOption.fromJson(Map<String, dynamic> json) {
    return AcademicYearOption(
      id: json['id'] as int,
      name: json['name'] as String,
      isCurrent: json['is_current'] as bool? ?? false,
    );
  }

  final int id;
  final String name;
  final bool isCurrent;
}

class TermColumn {
  const TermColumn({
    required this.id,
    required this.name,
    required this.from,
    required this.to,
    required this.inProgress,
  });

  factory TermColumn.fromJson(Map<String, dynamic> json) {
    return TermColumn(
      id: json['id'] as int,
      name: json['name'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      inProgress: json['in_progress'] as bool? ?? false,
    );
  }

  final int id;
  final String name;
  final String from;
  final String to;

  /// Still going: its figure will move.
  final bool inProgress;
}

/// One term's figure for a subject, a class, or a class's subject.
class TermFigure {
  const TermFigure({required this.average, required this.marksCounted, this.students, this.studentsBelowTheMark});

  factory TermFigure.fromJson(Map<String, dynamic> json) {
    return TermFigure(
      average: (json['average_percentage'] as num?)?.toDouble(),
      marksCounted: json['marks_counted'] as int? ?? 0,
      students: json['students'] as int?,
      studentsBelowTheMark: json['students_below_the_mark'] as int?,
    );
  }

  final double? average;
  final int marksCounted;
  final int? students;

  /// Students whose average in the subject is under the school's weak line;
  /// null where the school keeps none.
  final int? studentsBelowTheMark;
}

/// A line of the table: a subject, a class, or one class's subject, with a
/// figure (or null) per term.
class AcademicLine {
  const AcademicLine({required this.label, required this.terms, this.detail});

  /// [labelKey] names the field the row is labelled by; [detailKey] an
  /// optional second one shown beside it (the department, or the subject).
  factory AcademicLine.fromJson(Map<String, dynamic> json, {required String labelKey, String? detailKey}) {
    return AcademicLine(
      label: json[labelKey] as String? ?? '-',
      detail: detailKey == null ? null : json[detailKey] as String?,
      terms: (json['terms'] as List<dynamic>)
          .map((term) => term == null ? null : TermFigure.fromJson(term as Map<String, dynamic>))
          .toList(),
    );
  }

  final String label;
  final String? detail;
  final List<TermFigure?> terms;

  /// The last two terms with a figure, latest first - what "change" is
  /// measured between. Null when there are not two.
  (double, double)? get lastChange {
    final known = [for (final term in terms) ?term?.average];
    if (known.length < 2) return null;

    return (known.last, known[known.length - 2]);
  }
}

class AcademicOverview {
  const AcademicOverview({
    required this.years,
    required this.yearId,
    required this.yearName,
    required this.terms,
    this.termsSetUp = 0,
    required this.subjects,
    required this.classes,
    required this.cells,
    required this.passMark,
    required this.weakBelow,
  });

  factory AcademicOverview.fromJson(Map<String, dynamic> json) {
    final year = json['year'] as Map<String, dynamic>?;

    List<AcademicLine> lines(String key, String labelKey, String? detailKey) => (json[key] as List<dynamic>)
        .map((row) => AcademicLine.fromJson(row as Map<String, dynamic>, labelKey: labelKey, detailKey: detailKey))
        .toList();

    return AcademicOverview(
      years: (json['years'] as List<dynamic>)
          .map((row) => AcademicYearOption.fromJson(row as Map<String, dynamic>))
          .toList(),
      yearId: year?['id'] as int?,
      yearName: year?['name'] as String?,
      terms: (json['terms'] as List<dynamic>).map((row) => TermColumn.fromJson(row as Map<String, dynamic>)).toList(),
      termsSetUp: json['terms_set_up'] as int? ?? 0,
      subjects: lines('subjects', 'subject', 'department'),
      classes: lines('classes', 'class_section', null),
      cells: lines('cells', 'class_section', 'subject'),
      passMark: (json['pass_mark'] as num?)?.toDouble(),
      weakBelow: (json['weak_below'] as num?)?.toDouble(),
    );
  }

  final List<AcademicYearOption> years;
  final int? yearId;
  final String? yearName;
  final List<TermColumn> terms;

  /// Every term the year has, begun or not.
  final int termsSetUp;
  final List<AcademicLine> subjects;
  final List<AcademicLine> classes;

  /// Each class's subject: [AcademicLine.label] is the class,
  /// [AcademicLine.detail] the subject.
  final List<AcademicLine> cells;
  final double? passMark;
  final double? weakBelow;

  bool get isEmpty => subjects.isEmpty && classes.isEmpty;
}
