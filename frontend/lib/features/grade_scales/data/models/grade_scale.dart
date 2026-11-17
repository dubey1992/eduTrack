/// How a school grades with a scale (docs/document-styles.md): by marks and
/// percentage, by grade points (GPA), or by grades alone.
enum GradeScaleKind {
  percentage('percentage', 'Marks & percentage'),
  gpa('gpa', 'Grade points (GPA)'),
  grades('grades', 'Grades only');

  const GradeScaleKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static GradeScaleKind fromApiValue(String? value) =>
      GradeScaleKind.values.firstWhere((kind) => kind.apiValue == value, orElse: () => GradeScaleKind.percentage);
}

/// How a school turns a percentage into a grade (docs/assessments.md).
///
/// A band's percentages arrive as strings, the way money does, so a boundary
/// the school wrote as 90.00 is not rendered back as 90.0.
class GradeBand {
  const GradeBand({
    required this.id,
    required this.label,
    required this.minPercentage,
    required this.maxPercentage,
    required this.isFailing,
    this.gradePoint,
    this.description,
  });

  factory GradeBand.fromJson(Map<String, dynamic> json) {
    return GradeBand(
      id: json['id'] as int?,
      label: json['label'] as String,
      minPercentage: json['min_percentage'] as String,
      maxPercentage: json['max_percentage'] as String,
      isFailing: json['is_failing'] as bool,
      gradePoint: json['grade_point'] as String?,
      description: json['description'] as String?,
    );
  }

  /// Null for a row somebody has just added and not yet saved. Band ids are
  /// not sent back on a save: the set is replaced whole.
  final int? id;
  final String label;
  final String minPercentage;
  final String maxPercentage;
  final bool isFailing;

  /// A GPA scale's points for the band, as a string like the percentages.
  final String? gradePoint;

  /// What the grade means in words, printed in the report card's key.
  final String? description;

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'min_percentage': minPercentage,
      'max_percentage': maxPercentage,
      'is_failing': isFailing,
      'grade_point': gradePoint,
      'description': description,
    };
  }

  /// "10" or "3.5": a band's points without the zeros nobody reads.
  String? get points => gradePoint == null ? null : _tidy(gradePoint!);

  /// "81 - 90", with the trailing zeros of a whole number dropped, because
  /// "81.00 - 90.00" is harder to read at a glance and says no more.
  String get range => '${_tidy(minPercentage)} - ${_tidy(maxPercentage)}';

  static String _tidy(String percentage) {
    final parsed = double.tryParse(percentage);
    if (parsed == null) return percentage;
    if (parsed == parsed.roundToDouble()) return parsed.round().toString();

    // 32.50 -> 32.5: the second decimal is stored, never worth reading.
    return percentage.replaceFirst(RegExp(r'0+$'), '');
  }
}

class GradeScale {
  const GradeScale({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.isDefault,
    required this.bands,
    this.kind = GradeScaleKind.percentage,
    this.gpaMultiplier,
  });

  factory GradeScale.fromJson(Map<String, dynamic> json) {
    return GradeScale(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      isDefault: json['is_default'] as bool,
      bands: [for (final band in json['bands'] as List<dynamic>) GradeBand.fromJson(band as Map<String, dynamic>)],
      kind: GradeScaleKind.fromApiValue(json['kind'] as String?),
      gpaMultiplier: json['gpa_multiplier'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;
  final bool isDefault;

  /// Highest band first, as the API sends them.
  final List<GradeBand> bands;

  final GradeScaleKind kind;

  /// The school's own "percentage = GPA x 9.5", or null when it has none.
  final String? gpaMultiplier;
}
