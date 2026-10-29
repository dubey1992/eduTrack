import 'package:dio/dio.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/analytics/data/analytics_api.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/academic_overview.dart';
import 'package:edutrack_app/features/analytics/data/models/analytics_series.dart';
import 'package:edutrack_app/features/analytics/data/models/early_warning.dart';

/// What a School Admin may chart, in the order the API lists them.
const fakeAnalyticsMeasures = [
  AnalyticsMeasure(
    key: 'student_attendance_rate',
    label: 'Student attendance',
    unit: AnalyticsUnit.percent,
    snapshot: false,
  ),
  AnalyticsMeasure(key: 'fees_collected', label: 'Fees collected', unit: AnalyticsUnit.money, snapshot: false),
  AnalyticsMeasure(key: 'active_students', label: 'Students on roll', unit: AnalyticsUnit.count, snapshot: true),
];

/// Attendance over three months, the middle one without a register.
AnalyticsSeries fakeAttendanceSeries() => AnalyticsSeries.fromJson({
  'measure': 'student_attendance_rate',
  'label': 'Student attendance',
  'unit': 'percent',
  'interval': 'month',
  'from': '2026-07-01',
  'to': '2026-09-14',
  'points': [
    {'from': '2026-07-01', 'to': '2026-07-31', 'working_days': 23, 'value': 91.5},
    {'from': '2026-08-01', 'to': '2026-08-31', 'working_days': 0, 'value': null},
    {'from': '2026-09-01', 'to': '2026-09-14', 'working_days': 10, 'value': 88},
  ],
});

/// Fees in two currencies, never added together.
AnalyticsSeries fakeCollectedSeries() => AnalyticsSeries.fromJson({
  'measure': 'fees_collected',
  'label': 'Fees collected',
  'unit': 'money',
  'interval': 'month',
  'from': '2026-06-01',
  'to': '2026-07-15',
  'points': [
    {
      'from': '2026-06-01',
      'to': '2026-06-30',
      'working_days': 22,
      'amounts': [
        {'currency_code': 'INR', 'amount': '1000.00'},
      ],
    },
    {
      'from': '2026-07-01',
      'to': '2026-07-15',
      'working_days': 11,
      'amounts': [
        {'currency_code': 'INR', 'amount': '400.00'},
        {'currency_code': 'USD', 'amount': '10.00'},
      ],
    },
  ],
});

/// A snapshot figure before its first recording.
AnalyticsSeries fakeNotRecordedYetSeries() => AnalyticsSeries.fromJson({
  'measure': 'active_students',
  'label': 'Students on roll',
  'unit': 'count',
  'interval': 'month',
  'from': '2026-09-01',
  'to': '2026-09-14',
  'points': [
    {'from': '2026-09-01', 'to': '2026-09-14', 'working_days': 10, 'value': null},
  ],
});

/// 2026-27, two terms in: Physics fell from 75% to 50% in 8 A; Maths was 30%
/// in term 1 (under the 33% pass mark) and has no result in term 2.
Map<String, dynamic> fakeAcademicJson({List<dynamic>? terms}) => {
  'years': [
    {'id': 2, 'name': '2026-27', 'is_current': true},
    {'id': 1, 'name': '2025-26', 'is_current': false},
  ],
  'year': {'id': 2, 'name': '2026-27'},
  'terms_set_up': 3,
  'terms':
      terms ??
      [
        {'id': 11, 'name': 'Term 1', 'from': '2026-04-01', 'to': '2026-07-31', 'in_progress': false},
        {'id': 12, 'name': 'Term 2', 'from': '2026-08-01', 'to': '2026-09-14', 'in_progress': true},
      ],
  'subjects': [
    {
      'subject_id': 5,
      'subject': 'Maths',
      'department': 'Mathematics',
      'terms': [
        {'average_percentage': 30, 'marks_counted': 1},
        null,
      ],
    },
    {
      'subject_id': 4,
      'subject': 'Physics',
      'department': 'Science',
      'terms': [
        {'average_percentage': 75, 'marks_counted': 1},
        {'average_percentage': 50, 'marks_counted': 1},
      ],
    },
  ],
  'classes': [
    {
      'class_section_id': 3,
      'class_section': 'Grade 8 A',
      'terms': [
        {'average_percentage': 52.5, 'marks_counted': 2},
        {'average_percentage': 50, 'marks_counted': 1},
      ],
    },
  ],
  'cells': [
    {
      'class_section_id': 3,
      'class_section': 'Grade 8 A',
      'subject_id': 4,
      'subject': 'Physics',
      'department': 'Science',
      'terms': [
        {'average_percentage': 75, 'marks_counted': 1, 'students': 30, 'students_below_the_mark': 2},
        {'average_percentage': 50, 'marks_counted': 1, 'students': 30, 'students_below_the_mark': 9},
      ],
    },
  ],
  'pass_mark': 33,
  'weak_below': 40,
};

/// Two flagged students in Grade 8 A: one at high risk, one at risk.
EarlyWarningPage fakeEarlyWarningPage({int high = 1, int atRisk = 1, EarlyWarningLevel? level}) {
  final rows = [
    if (high > 0 && level != EarlyWarningLevel.atRisk)
      {
        'student_id': 7,
        'name': 'Zara Khan',
        'admission_number': 'ADM-0007',
        'class_section_id': 3,
        'class_section': 'Grade 8 A',
        'level': 'high',
        'signals': [
          {
            'code': 'low_attendance',
            'value': 62,
            'previous': null,
            'message': 'Attendance 62% over the last 30 school days, below 75%.',
          },
          {
            'code': 'falling_marks',
            'value': 48,
            'previous': 71,
            'message': 'Test average down 23 points, from 71% to 48%.',
          },
        ],
      },
    if (atRisk > 0 && level != EarlyWarningLevel.high)
      {
        'student_id': 9,
        'name': 'Arjun Kumar',
        'admission_number': 'ADM-0042',
        'class_section_id': 3,
        'class_section': 'Grade 8 A',
        'level': 'at_risk',
        'signals': [
          {
            'code': 'falling_attendance',
            'value': 86.7,
            'previous': 100,
            'message': 'Attendance down 13.3 points, from 100% to 86.7%.',
          },
        ],
      },
  ];

  return EarlyWarningPage.fromJson({
    'data': rows,
    'meta': {'current_page': 1, 'last_page': 1, 'total': rows.length, 'per_page': 20},
    'summary': {
      'as_of': '2026-09-14',
      'thresholds': {'attendance_below': 75, 'drop_points': 10, 'pass_mark': 33},
      'windows': <String, dynamic>{},
      'counts': {'high': high, 'at_risk': atRisk},
    },
  });
}

class FakeAnalyticsRepository extends AnalyticsRepository {
  FakeAnalyticsRepository({
    this.measureList = fakeAnalyticsMeasures,
    this.failure,
    this.seriesByMeasure = const {},
    this.flaggedHigh = 0,
    this.flaggedAtRisk = 0,
    this.earlyWarningFailure,
    this.academicJson,
  }) : super(AnalyticsApi(Dio()));

  /// What the "Subjects & classes" view gets; [fakeAcademicJson] if null.
  final Map<String, dynamic>? academicJson;

  final academicAsked = <({int? schoolId, int? academicYearId})>[];

  @override
  Future<AcademicOverview> academic({int? schoolId, int? academicYearId}) async {
    academicAsked.add((schoolId: schoolId, academicYearId: academicYearId));
    if (failure != null) throw failure!;

    return AcademicOverview.fromJson(academicJson ?? fakeAcademicJson());
  }

  /// How many students the early-warning list says are flagged.
  final int flaggedHigh;
  final int flaggedAtRisk;
  final Failure? earlyWarningFailure;

  final earlyWarningAsked = <({int? schoolId, EarlyWarningLevel? level, int page, int perPage})>[];

  @override
  Future<EarlyWarningPage> earlyWarning({
    int? schoolId,
    int? classSectionId,
    EarlyWarningLevel? level,
    int page = 1,
    int perPage = 20,
  }) async {
    earlyWarningAsked.add((schoolId: schoolId, level: level, page: page, perPage: perPage));
    if (earlyWarningFailure != null) throw earlyWarningFailure!;

    return fakeEarlyWarningPage(high: flaggedHigh, atRisk: flaggedAtRisk, level: level);
  }

  final List<AnalyticsMeasure> measureList;

  /// Thrown by every series request when set.
  final Failure? failure;

  /// Series by measure key, over the defaults below.
  final Map<String, AnalyticsSeries> seriesByMeasure;

  final asked = <({String measure, AnalyticsInterval interval, int? schoolId, String? from, String? to})>[];

  @override
  Future<List<AnalyticsMeasure>> measures() async => measureList;

  @override
  Future<AnalyticsSeries> series(
    String measure, {
    AnalyticsInterval interval = AnalyticsInterval.month,
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    asked.add((measure: measure, interval: interval, schoolId: schoolId, from: from, to: to));
    if (failure != null) throw failure!;

    return seriesByMeasure[measure] ??
        switch (measure) {
          'fees_collected' => fakeCollectedSeries(),
          'active_students' => fakeNotRecordedYetSeries(),
          _ => fakeAttendanceSeries(),
        };
  }
}
