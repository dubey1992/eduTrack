import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/analytics/data/analytics_api.dart';
import 'package:edutrack_app/features/analytics/data/analytics_repository.dart';
import 'package:edutrack_app/features/analytics/data/models/analytics_series.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned response, and remembers what was
/// asked - so the tests see exactly the query the server would.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  RequestOptions? asked;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked = options;

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AnalyticsRepository _repository(_CannedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter;

  return AnalyticsRepository(AnalyticsApi(dio));
}

const _attendance = {
  'measure': 'student_attendance_rate',
  'label': 'Student attendance',
  'unit': 'percent',
  'interval': 'week',
  'from': '2026-08-31',
  'to': '2026-09-11',
  'points': [
    {'from': '2026-08-31', 'to': '2026-09-06', 'working_days': 0, 'value': null},
    {'from': '2026-09-07', 'to': '2026-09-11', 'working_days': 5, 'value': 60},
  ],
};

const _collected = {
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
};

void main() {
  group('AnalyticsSeries.fromJson', () {
    test('a week of holidays is a gap, not a zero', () {
      final series = AnalyticsSeries.fromJson(_attendance);

      expect(series.unit, AnalyticsUnit.percent);
      expect(series.interval, AnalyticsInterval.week);
      expect(series.points.first.isGap, isTrue);
      expect(series.points.first.workingDays, 0);
      expect(series.points.last.value, 60.0);
      expect(series.isEmpty, isFalse);
    });

    test('money keeps one amount per currency, exactly as sent', () {
      final series = AnalyticsSeries.fromJson(_collected);

      expect(series.unit, AnalyticsUnit.money);
      expect(series.currencies, ['INR', 'USD']);
      expect(series.points.last.amounts!.map((line) => (line.currencyCode, line.amount)), [
        ('INR', '400.00'),
        ('USD', '10.00'),
      ]);
      expect(series.points.last.isGap, isFalse);
    });

    test('a snapshot measure before its first recording has nothing to draw', () {
      final series = AnalyticsSeries.fromJson({
        ..._attendance,
        'measure': 'active_students',
        'unit': 'count',
        'points': [
          {'from': '2026-08-01', 'to': '2026-08-31', 'working_days': 21, 'value': null},
        ],
      });

      expect(series.isEmpty, isTrue);
    });
  });

  group('AnalyticsRepository', () {
    test('asks for the measure, interval and narrowing it was given, and nothing else', () async {
      final adapter = _CannedAdapter(200, _attendance);

      await _repository(adapter)
          .series('student_attendance_rate', interval: AnalyticsInterval.week, from: '2026-08-31', classSectionId: 4);

      expect(adapter.asked!.path, '/analytics/series');
      expect(adapter.asked!.queryParameters, {
        'measure': 'student_attendance_rate',
        'interval': 'week',
        'from': '2026-08-31',
        'class_section_id': 4,
      });
    });

    test('reads the measures this person may chart', () async {
      final adapter = _CannedAdapter(200, {
        'data': [
          {'key': 'active_students', 'label': 'Students on roll', 'unit': 'count', 'snapshot': true},
        ],
      });

      final measures = await _repository(adapter).measures();

      expect(measures.single.key, 'active_students');
      expect(measures.single.snapshot, isTrue);
      expect(measures.single.unit, AnalyticsUnit.count);
    });

    test('a switched-off module comes back as that failure, not a crash', () async {
      final adapter = _CannedAdapter(403, {
        'code': 'MODULE_DISABLED',
        'message': 'Fee Management is switched off for this school.',
        'details': <String, dynamic>{},
      });

      await expectLater(
        _repository(adapter).series('fees_collected'),
        throwsA(isA<Failure>().having((failure) => failure.isModuleDisabled, 'isModuleDisabled', isTrue)),
      );
    });

    test('a refused range surfaces the field message', () async {
      final adapter = _CannedAdapter(422, {
        'code': 'VALIDATION_ERROR',
        'message': 'The given data was invalid.',
        'details': {
          'errors': {
            'from': ['A chart by week covers at most 53 weeks. Pick a shorter range.'],
          },
        },
      });

      await expectLater(
        _repository(adapter).series('student_attendance_rate', interval: AnalyticsInterval.week, from: '2025-01-01'),
        throwsA(
          isA<Failure>().having(
            (failure) => failure.message,
            'message',
            'A chart by week covers at most 53 weeks. Pick a shorter range.',
          ),
        ),
      );
    });
  });
}
