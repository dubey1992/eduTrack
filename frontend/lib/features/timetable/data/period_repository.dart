import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/period.dart';
import 'period_api.dart';

final periodRepositoryProvider = Provider<PeriodRepository>((ref) => PeriodRepository(ref.watch(periodApiProvider)));

class PeriodRepository {
  PeriodRepository(this._api);

  final PeriodApi _api;

  Future<List<Period>> list({int? schoolId}) async {
    try {
      return await _api.list(schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Period> create({
    int? schoolId,
    required int periodNumber,
    required String startTime,
    required String endTime,
  }) async {
    try {
      return await _api.create(schoolId: schoolId, periodNumber: periodNumber, startTime: startTime, endTime: endTime);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Period> update(int periodId, {int? periodNumber, String? startTime, String? endTime}) async {
    try {
      return await _api.update(periodId, periodNumber: periodNumber, startTime: startTime, endTime: endTime);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int periodId) async {
    try {
      await _api.delete(periodId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
