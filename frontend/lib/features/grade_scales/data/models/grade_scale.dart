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
  });

  factory GradeBand.fromJson(Map<String, dynamic> json) {
    return GradeBand(
      id: json['id'] as int?,
      label: json['label'] as String,
      minPercentage: json['min_percentage'] as String,
      maxPercentage: json['max_percentage'] as String,
      isFailing: json['is_failing'] as bool,
    );
  }

  /// Null for a row somebody has just added and not yet saved. Band ids are
  /// not sent back on a save: the set is replaced whole.
  final int? id;
  final String label;
  final String minPercentage;
  final String maxPercentage;
  final bool isFailing;

  Map<String, dynamic> toJson() {
    return {'label': label, 'min_percentage': minPercentage, 'max_percentage': maxPercentage, 'is_failing': isFailing};
  }

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
  });

  factory GradeScale.fromJson(Map<String, dynamic> json) {
    return GradeScale(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      isDefault: json['is_default'] as bool,
      bands: [for (final band in json['bands'] as List<dynamic>) GradeBand.fromJson(band as Map<String, dynamic>)],
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;
  final bool isDefault;

  /// Highest band first, as the API sends them.
  final List<GradeBand> bands;
}
