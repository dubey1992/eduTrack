import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'holiday_api.dart';
import 'models/holiday.dart';

final holidayRepositoryProvider = Provider<HolidayRepository>(
  (ref) => HolidayRepository(ref.watch(holidayApiProvider)),
);

class HolidayRepository {
  HolidayRepository(this._api);

  final HolidayApi _api;

  Future<PaginatedResponse<Holiday>> listPage({
    int? schoolId,
    String? dateFrom,
    String? dateTo,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(schoolId: schoolId, dateFrom: dateFrom, dateTo: dateTo, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Holiday> create({
    int? schoolId,
    required String name,
    required HolidayType type,
    required String startDate,
    required String endDate,
  }) async {
    try {
      return await _api.create(schoolId: schoolId, name: name, type: type, startDate: startDate, endDate: endDate);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Holiday> update(int holidayId, {String? name, HolidayType? type, String? startDate, String? endDate}) async {
    try {
      return await _api.update(holidayId, name: name, type: type, startDate: startDate, endDate: endDate);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int holidayId) async {
    try {
      await _api.delete(holidayId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
