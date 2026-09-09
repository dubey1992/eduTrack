import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/period.dart';

final periodApiProvider = Provider<PeriodApi>((ref) => PeriodApi(ref.watch(dioClientProvider)));

class PeriodApi {
  PeriodApi(this._dio);

  final Dio _dio;

  Future<List<Period>> list({int? schoolId}) async {
    final response = await _dio.get('/periods', queryParameters: {'school_id': ?schoolId});
    return (response.data as List).cast<Map<String, dynamic>>().map(Period.fromJson).toList();
  }

  Future<Period> create({
    int? schoolId,
    required int periodNumber,
    required String startTime,
    required String endTime,
  }) async {
    final response = await _dio.post(
      '/periods',
      data: {'school_id': schoolId, 'period_number': periodNumber, 'start_time': startTime, 'end_time': endTime},
    );
    return Period.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Period> update(int periodId, {int? periodNumber, String? startTime, String? endTime}) async {
    final response = await _dio.patch(
      '/periods/$periodId',
      data: {'period_number': ?periodNumber, 'start_time': ?startTime, 'end_time': ?endTime},
    );
    return Period.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int periodId) async {
    await _dio.delete('/periods/$periodId');
  }
}
