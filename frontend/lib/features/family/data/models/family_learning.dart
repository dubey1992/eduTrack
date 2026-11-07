/// A child's learning, as the Family app shows it (school/family_learning.py,
/// docs/parent-student-app.md F2).
library;

class SchoolTerm {
  const SchoolTerm({required this.id, required this.name, required this.start, required this.end});

  factory SchoolTerm.fromJson(Map<String, dynamic> json) => SchoolTerm(
    id: json['id'] as int,
    name: json['name'] as String,
    start: DateTime.parse(json['start_date'] as String),
    end: DateTime.parse(json['end_date'] as String),
  );

  final int id;
  final String name;
  final DateTime start;
  final DateTime end;
}

/// A mark or percentage as the API sends it ("18.00"), as a person reads
/// it ("18"); "17.50" stays "17.5".
String readableNumber(String? value) {
  if (value == null) return '-';
  final number = double.tryParse(value);
  if (number == null) return value;
  return number == number.roundToDouble() ? number.toInt().toString() : number.toStringAsFixed(1);
}

class TestResult {
  const TestResult({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    required this.maxMarks,
    required this.marksObtained,
    required this.isAbsent,
    required this.percentage,
    required this.grade,
    required this.remarks,
    required this.classAverage,
  });

  factory TestResult.fromJson(Map<String, dynamic> json) => TestResult(
    id: json['id'] as int,
    title: json['title'] as String,
    type: json['type'] as String,
    date: DateTime.tryParse(json['date'] as String? ?? ''),
    maxMarks: json['max_marks'] as String?,
    marksObtained: json['marks_obtained'] as String?,
    isAbsent: json['is_absent'] as bool,
    percentage: json['percentage'] as String?,
    grade: json['grade'] as String?,
    remarks: json['remarks'] as String?,
    classAverage: json['class_average_percentage'] as String?,
  );

  final int id;
  final String title;
  final String type;
  final DateTime? date;
  final String? maxMarks;
  final String? marksObtained;
  final bool isAbsent;
  final String? percentage;
  final String? grade;
  final String? remarks;

  /// Null unless the school shows parents the class average.
  final String? classAverage;

  /// "18 / 20", or "Absent".
  String get score => isAbsent ? 'Absent' : '${readableNumber(marksObtained)} / ${readableNumber(maxMarks)}';
}

class SubjectResults {
  const SubjectResults({
    required this.subject,
    required this.average,
    required this.grade,
    required this.classAverage,
    required this.tests,
  });

  factory SubjectResults.fromJson(Map<String, dynamic> json) => SubjectResults(
    subject: json['subject'] as String,
    average: json['average_percentage'] as String?,
    grade: json['grade'] as String?,
    classAverage: json['class_average_percentage'] as String?,
    tests: [for (final t in json['tests'] as List<dynamic>) TestResult.fromJson(t as Map<String, dynamic>)],
  );

  final String subject;
  final String? average;
  final String? grade;
  final String? classAverage;
  final List<TestResult> tests;
}

class FamilyResults {
  const FamilyResults({
    required this.terms,
    required this.term,
    required this.showsClassAverage,
    required this.subjects,
    required this.remark,
    required this.reportAvailable,
    required this.reportFrom,
    this.weakBelow = 40,
  });

  factory FamilyResults.fromJson(Map<String, dynamic> json) {
    final term = json['term'] as Map<String, dynamic>?;
    final report = json['progress_report'] as Map<String, dynamic>;

    return FamilyResults(
      terms: [for (final t in json['terms'] as List<dynamic>) SchoolTerm.fromJson(t as Map<String, dynamic>)],
      term: term == null ? null : SchoolTerm.fromJson(term),
      showsClassAverage: json['shows_class_average'] as bool,
      subjects: [for (final s in json['subjects'] as List<dynamic>) SubjectResults.fromJson(s as Map<String, dynamic>)],
      remark: json['remark'] as String?,
      reportAvailable: report['available'] as bool,
      reportFrom: DateTime.tryParse(report['from'] as String? ?? ''),
      weakBelow: (json['weak_below_percentage'] as num?)?.toDouble() ?? 40,
    );
  }

  /// Every term of the child's year, newest first.
  final List<SchoolTerm> terms;

  /// The term shown; null before the school has set terms up.
  final SchoolTerm? term;
  final bool showsClassAverage;
  final List<SubjectResults> subjects;

  /// The class teacher's remark for the term.
  final String? remark;
  final bool reportAvailable;

  /// When the term's progress report will be ready.
  final DateTime? reportFrom;

  /// The school's line for a weak result: only below it is a mark red.
  final double weakBelow;
}

class WeekPeriod {
  const WeekPeriod({required this.startTime, required this.endTime, required this.subject, required this.teacher});

  factory WeekPeriod.fromJson(Map<String, dynamic> json) => WeekPeriod(
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    subject: json['subject'] as String?,
    teacher: json['teacher'] as String?,
  );

  final String startTime;
  final String endTime;
  final String? subject;
  final String? teacher;
}

class SchoolDay {
  const SchoolDay({required this.day, required this.isHalfDay, required this.periods, required this.breaks});

  factory SchoolDay.fromJson(Map<String, dynamic> json) => SchoolDay(
    day: json['day'] as String,
    isHalfDay: json['shape'] == 'half',
    periods: [for (final p in json['periods'] as List<dynamic>) WeekPeriod.fromJson(p as Map<String, dynamic>)],
    breaks: [
      for (final b in json['breaks'] as List<dynamic>)
        (
          name: (b as Map<String, dynamic>)['name'] as String,
          startTime: b['start_time'] as String,
          endTime: b['end_time'] as String,
        ),
    ],
  );

  /// "monday".
  final String day;
  final bool isHalfDay;
  final List<WeekPeriod> periods;
  final List<({String name, String startTime, String endTime})> breaks;

  String get label => '${day[0].toUpperCase()}${day.substring(1)}';

  String get shortLabel => label.substring(0, 3);
}

class FamilyWeek {
  const FamilyWeek({required this.today, required this.days});

  factory FamilyWeek.fromJson(Map<String, dynamic> json) => FamilyWeek(
    today: json['today'] as String,
    days: [for (final d in json['days'] as List<dynamic>) SchoolDay.fromJson(d as Map<String, dynamic>)],
  );

  final String today;
  final List<SchoolDay> days;
}

class SubjectSyllabus {
  const SubjectSyllabus({
    required this.subject,
    required this.total,
    required this.covered,
    required this.percent,
    required this.nextTopics,
  });

  factory SubjectSyllabus.fromJson(Map<String, dynamic> json) => SubjectSyllabus(
    subject: json['subject'] as String,
    total: json['total_topics'] as int,
    covered: json['covered_topics'] as int,
    percent: json['percent'] as int,
    nextTopics: [for (final t in json['next_topics'] as List<dynamic>) t as String],
  );

  final String subject;
  final int total;
  final int covered;
  final int percent;
  final List<String> nextTopics;
}
