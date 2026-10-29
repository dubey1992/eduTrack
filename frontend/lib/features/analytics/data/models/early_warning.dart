/// Student early warning (docs/analytics.md, A3), as
/// `GET /analytics/early-warning` sends it.
///
/// Every flag carries its reasons as sentences with the numbers in them, so
/// the screen shows the server's words rather than composing its own.
library;

enum EarlyWarningLevel {
  high('high', 'High risk'),
  atRisk('at_risk', 'At risk');

  const EarlyWarningLevel(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static EarlyWarningLevel fromApi(String value) =>
      EarlyWarningLevel.values.firstWhere((level) => level.apiValue == value, orElse: () => EarlyWarningLevel.atRisk);
}

class EarlyWarningSignal {
  const EarlyWarningSignal({required this.code, required this.message, this.value, this.previous});

  factory EarlyWarningSignal.fromJson(Map<String, dynamic> json) {
    return EarlyWarningSignal(
      code: json['code'] as String,
      message: json['message'] as String,
      value: (json['value'] as num?)?.toDouble(),
      previous: (json['previous'] as num?)?.toDouble(),
    );
  }

  final String code;
  final String message;
  final double? value;
  final double? previous;

  /// Attendance or tests - which page a teacher goes to next.
  bool get isAttendance => code.contains('attendance');
}

class FlaggedStudent {
  const FlaggedStudent({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.classSection,
    required this.level,
    required this.signals,
  });

  factory FlaggedStudent.fromJson(Map<String, dynamic> json) {
    return FlaggedStudent(
      studentId: json['student_id'] as int,
      name: json['name'] as String,
      admissionNumber: json['admission_number'] as String?,
      classSection: json['class_section'] as String?,
      level: EarlyWarningLevel.fromApi(json['level'] as String),
      signals: (json['signals'] as List<dynamic>)
          .map((signal) => EarlyWarningSignal.fromJson(signal as Map<String, dynamic>))
          .toList(),
    );
  }

  final int studentId;
  final String name;
  final String? admissionNumber;
  final String? classSection;
  final EarlyWarningLevel level;
  final List<EarlyWarningSignal> signals;
}

/// The lines a school judges by, and the windows they were applied to.
class EarlyWarningSummary {
  const EarlyWarningSummary({
    required this.asOf,
    required this.attendanceBelow,
    required this.dropPoints,
    required this.passMark,
    required this.highCount,
    required this.atRiskCount,
  });

  factory EarlyWarningSummary.fromJson(Map<String, dynamic> json) {
    final thresholds = json['thresholds'] as Map<String, dynamic>;
    final counts = json['counts'] as Map<String, dynamic>;

    return EarlyWarningSummary(
      asOf: json['as_of'] as String,
      attendanceBelow: thresholds['attendance_below'] as int,
      dropPoints: thresholds['drop_points'] as int,
      passMark: thresholds['pass_mark'] as int,
      highCount: counts['high'] as int,
      atRiskCount: counts['at_risk'] as int,
    );
  }

  final String asOf;
  final int attendanceBelow;
  final int dropPoints;
  final int passMark;
  final int highCount;
  final int atRiskCount;

  int get flaggedCount => highCount + atRiskCount;
}

/// One page of the list, with the whole list's counts beside it.
class EarlyWarningPage {
  const EarlyWarningPage({
    required this.students,
    required this.summary,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });

  factory EarlyWarningPage.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>;

    return EarlyWarningPage(
      students: (json['data'] as List<dynamic>)
          .map((row) => FlaggedStudent.fromJson(row as Map<String, dynamic>))
          .toList(),
      summary: EarlyWarningSummary.fromJson(json['summary'] as Map<String, dynamic>),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
      perPage: meta['per_page'] as int,
    );
  }

  final List<FlaggedStudent> students;
  final EarlyWarningSummary summary;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;
}
