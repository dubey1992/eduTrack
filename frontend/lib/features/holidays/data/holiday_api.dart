import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/holiday.dart';

final holidayApiProvider = Provider<HolidayApi>((ref) => HolidayApi(ref.watch(dioClientProvider)));

class HolidayApi {
  HolidayApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<Holiday>> list({
    int? schoolId,
    String? dateFrom,
    String? dateTo,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/holidays',
      queryParameters: {
        'school_id': ?schoolId,
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Holiday.fromJson);
  }

  Future<Holiday> create({
    int? schoolId,
    required String name,
    required HolidayType type,
    required String startDate,
    required String endDate,
  }) async {
    final response = await _dio.post(
      '/holidays',
      data: {'school_id': schoolId, 'name': name, 'type': type.apiValue, 'start_date': startDate, 'end_date': endDate},
    );
    return Holiday.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Holiday> update(int holidayId, {String? name, HolidayType? type, String? startDate, String? endDate}) async {
    final response = await _dio.patch(
      '/holidays/$holidayId',
      data: {'name': ?name, 'type': ?type?.apiValue, 'start_date': ?startDate, 'end_date': ?endDate},
    );
    return Holiday.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int holidayId) async {
    await _dio.delete('/holidays/$holidayId');
  }
}
