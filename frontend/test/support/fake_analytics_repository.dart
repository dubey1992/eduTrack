import 'package:dio/dio.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/analytics/data/analytics_api.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/academic_overview.dart';
import 'package:edutrack_app/features/analytics/data/models/analytics_series.dart';
import 'package:edutrack_app/features/analytics/data/models/early_warning.dart';
import 'package:edutrack_app/features/analytics/data/models/finance_overview.dart';
import 'package:edutrack_app/features/analytics/data/models/platform_overview.dart';
import 'package:edutrack_app/features/analytics/data/models/transport_overview.dart';

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

/// A school billing in rupees and, for one family, dollars: two months of
/// collection, July's overdue ages recorded, one class, and the payroll
/// section when [withPayroll].
Map<String, dynamic> fakeFinanceJson({bool withPayroll = true}) => {
  'as_of': '2026-07-15',
  'months': [
    {'from': '2026-06-01', 'to': '2026-06-30'},
    {'from': '2026-07-01', 'to': '2026-07-15'},
  ],
  'collection': [
    {
      'from': '2026-06-01',
      'to': '2026-06-30',
      'amounts': [
        {'currency_code': 'INR', 'due': '0.00', 'collected': '500.00', 'paid_so_far': '0.00', 'rate': null},
      ],
    },
    {
      'from': '2026-07-01',
      'to': '2026-07-15',
      'amounts': [
        {'currency_code': 'INR', 'due': '1000.00', 'collected': '1000.00', 'paid_so_far': '250.00', 'rate': 25.0},
        {'currency_code': 'USD', 'due': '40.00', 'collected': '10.00', 'paid_so_far': '10.00', 'rate': 25.0},
      ],
    },
  ],
  'overdue_by_age': [
    {'from': '2026-06-01', 'to': '2026-06-30', 'as_of': null, 'amounts': null},
    {
      'from': '2026-07-01',
      'to': '2026-07-15',
      'as_of': '2026-07-15',
      'amounts': [
        {'currency_code': 'INR', 'overdue_0_30': '1000.00', 'overdue_31_60': '0.00', 'overdue_61_plus': '750.00'},
      ],
    },
  ],
  'by_class': [
    {
      'class_section_id': 3,
      'class_section': 'Class 8 A',
      'currency_code': 'INR',
      'charged': '2000.00',
      'paid': '1000.00',
      'outstanding': '1000.00',
      'overdue': '1000.00',
      'rate': 50.0,
    },
  ],
  'upcoming': [
    {'from': '2026-08-01', 'to': '2026-08-31', 'amounts': <dynamic>[]},
    {'from': '2026-09-01', 'to': '2026-09-30', 'amounts': <dynamic>[]},
    {
      'from': '2026-10-01',
      'to': '2026-10-31',
      'amounts': [
        {'currency_code': 'INR', 'due': '1000.00'},
      ],
    },
  ],
  if (withPayroll)
    'fees_vs_payroll': [
      {'from': '2026-06-01', 'to': '2026-06-30', 'amounts': <dynamic>[]},
      {
        'from': '2026-07-01',
        'to': '2026-07-15',
        'amounts': [
          {'currency_code': 'INR', 'fees_in': '1000.00', 'payroll_out': '800.00'},
        ],
      },
    ],
};

/// Route A over two months: September with a late stop, and Market listed
/// as the stop most often late.
/// Two months of the whole platform: Sunrise (INR) busy, Lagos (NGN) quiet,
/// one school closed. September's payments come in two currencies.
Map<String, dynamic> fakePlatformJson({List<dynamic>? schools}) => {
  'as_of': '2026-09-14',
  'totals': {'schools_active': 2, 'schools_inactive': 1, 'students': 420, 'staff': 35, 'users': 61},
  'months': [
    {
      'from': '2026-08-01',
      'to': '2026-08-31',
      'new_schools': 2,
      'sign_ins': 40,
      'active_users': 12,
      'messages': {
        'sms': {'sent': 0, 'failed': 0},
        'whatsapp': {'sent': 0, 'failed': 0},
        'email': {'sent': 5, 'failed': 0},
      },
      'payments': <dynamic>[],
      'early_access_requests': 3,
      'demo_requests': 0,
    },
    {
      'from': '2026-09-01',
      'to': '2026-09-14',
      'new_schools': 1,
      'sign_ins': 75,
      'active_users': 18,
      'messages': {
        'sms': {'sent': 120, 'failed': 4},
        'whatsapp': {'sent': 30, 'failed': 0},
        'email': {'sent': 0, 'failed': 0},
      },
      'payments': [
        {'currency_code': 'INR', 'amount': '50000.00'},
        {'currency_code': 'NGN', 'amount': '300000.00'},
      ],
      'early_access_requests': 1,
      'demo_requests': 2,
    },
  ],
  'schools':
      schools ??
      [
        {
          'school_id': 1,
          'name': 'Sunrise School',
          'city': 'Pune',
          'country': 'IN',
          'status': 'active',
          'students': 400,
          'staff': 30,
          'last_sign_in': '2026-09-12T09:00:00+00:00',
          'last_sign_in_label': '09/12/2026',
          'recent_sign_ins': 70,
          'recent_messages': 150,
        },
        {
          'school_id': 2,
          'name': 'Lagos Academy',
          'city': 'Lagos',
          'country': 'NG',
          'status': 'active',
          'students': 20,
          'staff': 5,
          'last_sign_in': null,
          'last_sign_in_label': null,
          'recent_sign_ins': 0,
          'recent_messages': 0,
        },
      ],
  'modules': [
    {'module': 'transport', 'label': 'Transport', 'schools_on': 1, 'schools': 2},
  ],
  'recent_days': 30,
};

Map<String, dynamic> fakeTransportJson({bool withRoutes = true}) => {
  'as_of': '2026-09-14',
  'late_after_minutes': 10,
  'months': [
    {'from': '2026-08-01', 'to': '2026-08-31'},
    {'from': '2026-09-01', 'to': '2026-09-14'},
  ],
  'routes': [
    if (withRoutes)
      {
        'route_id': 1,
        'route': 'Route A',
        'months': [
          {
            'from': '2026-08-01',
            'to': '2026-08-31',
            'service': {'working_days': 21, 'days_run': 0, 'trips_completed': 0, 'trips_cancelled': 0},
            'riders': {'on_list': 0, 'boarded': 0, 'absent': 0, 'boarded_rate': null},
            'on_time': {'arrivals': 0, 'late': 0, 'on_time_rate': null, 'average_minutes_late': null},
            'length': {'trips': 0, 'average_minutes': null, 'longest_minutes': null},
          },
          {
            'from': '2026-09-01',
            'to': '2026-09-14',
            'service': {'working_days': 10, 'days_run': 2, 'trips_completed': 3, 'trips_cancelled': 1},
            'riders': {'on_list': 4, 'boarded': 3, 'absent': 1, 'boarded_rate': 75.0},
            'on_time': {'arrivals': 3, 'late': 1, 'on_time_rate': 66.7, 'average_minutes_late': 16.0},
            'length': {'trips': 2, 'average_minutes': 50.0, 'longest_minutes': 60.0},
          },
        ],
      },
  ],
  'late_stops': [
    if (withRoutes)
      {
        'stop_id': 2,
        'stop': 'Market',
        'route': 'Route A',
        'arrivals': 2,
        'late': 2,
        'late_rate': 100.0,
        'average_minutes_late': 20.0,
      },
  ],
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
    this.financeJson,
    this.transportJson,
    this.platformJson,
  }) : super(AnalyticsApi(Dio()));

  /// What the Platform view gets; [fakePlatformJson] if null.
  final Map<String, dynamic>? platformJson;

  var platformAsked = 0;

  @override
  Future<PlatformOverview> platform() async {
    platformAsked++;
    if (failure != null) throw failure!;

    return PlatformOverview.fromJson(platformJson ?? fakePlatformJson());
  }

  /// What the Transport view gets; [fakeTransportJson] if null.
  final Map<String, dynamic>? transportJson;

  final transportAsked = <int?>[];

  @override
  Future<TransportOverview> transport({int? schoolId}) async {
    transportAsked.add(schoolId);
    if (failure != null) throw failure!;

    return TransportOverview.fromJson(transportJson ?? fakeTransportJson());
  }

  /// What the Finance view gets; [fakeFinanceJson] if null.
  final Map<String, dynamic>? financeJson;

  final financeAsked = <int?>[];

  @override
  Future<FinanceOverview> finance({int? schoolId, String? from, String? to}) async {
    financeAsked.add(schoolId);
    if (failure != null) throw failure!;

    return FinanceOverview.fromJson(financeJson ?? fakeFinanceJson());
  }

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
