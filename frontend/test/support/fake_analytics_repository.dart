import 'package:dio/dio.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/analytics/data/analytics_api.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/analytics_series.dart';

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

class FakeAnalyticsRepository extends AnalyticsRepository {
  FakeAnalyticsRepository({this.measureList = fakeAnalyticsMeasures, this.failure, this.seriesByMeasure = const {}})
    : super(AnalyticsApi(Dio()));

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
