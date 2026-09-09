import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/academic_year.dart';

final academicYearApiProvider = Provider<AcademicYearApi>((ref) => AcademicYearApi(ref.watch(dioClientProvider)));

class AcademicYearApi {
  AcademicYearApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<AcademicYear>> list({int? schoolId, int? page, int? perPage}) async {
    final response = await _dio.get(
      '/academic-years',
      queryParameters: {'school_id': ?schoolId, 'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, AcademicYear.fromJson);
  }

  Future<AcademicYear> create({
    int? schoolId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required bool isCurrent,
  }) async {
    final response = await _dio.post(
      '/academic-years',
      data: {
        'school_id': schoolId,
        'name': name,
        'start_date': DateFormat('yyyy-MM-dd').format(startDate),
        'end_date': DateFormat('yyyy-MM-dd').format(endDate),
        'is_current': isCurrent,
      },
    );

    return AcademicYear.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcademicYear> update(int academicYearId, {String? name, DateTime? startDate, DateTime? endDate}) async {
    final formattedStart = startDate == null ? null : DateFormat('yyyy-MM-dd').format(startDate);
    final formattedEnd = endDate == null ? null : DateFormat('yyyy-MM-dd').format(endDate);

    final response = await _dio.patch(
      '/academic-years/$academicYearId',
      data: {'name': ?name, 'start_date': ?formattedStart, 'end_date': ?formattedEnd},
    );

    return AcademicYear.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AcademicYear> setCurrent(int academicYearId) async {
    final response = await _dio.patch('/academic-years/$academicYearId/set-current');
    return AcademicYear.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int academicYearId) async {
    await _dio.delete('/academic-years/$academicYearId');
  }
}
