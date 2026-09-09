import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'academic_year_api.dart';
import 'models/academic_year.dart';

final academicYearRepositoryProvider = Provider<AcademicYearRepository>(
  (ref) => AcademicYearRepository(ref.watch(academicYearApiProvider)),
);

class AcademicYearRepository {
  AcademicYearRepository(this._api);

  final AcademicYearApi _api;

  Future<List<AcademicYear>> list({int? schoolId}) async {
    try {
      final page = await _api.list(schoolId: schoolId);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<AcademicYear>> listPage({int? schoolId, required int page, required int perPage}) async {
    try {
      return await _api.list(schoolId: schoolId, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AcademicYear> create({
    int? schoolId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required bool isCurrent,
  }) async {
    try {
      return await _api.create(
        schoolId: schoolId,
        name: name,
        startDate: startDate,
        endDate: endDate,
        isCurrent: isCurrent,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AcademicYear> update(int academicYearId, {String? name, DateTime? startDate, DateTime? endDate}) async {
    try {
      return await _api.update(academicYearId, name: name, startDate: startDate, endDate: endDate);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AcademicYear> setCurrent(int academicYearId) async {
    try {
      return await _api.setCurrent(academicYearId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int academicYearId) async {
    try {
      await _api.delete(academicYearId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
