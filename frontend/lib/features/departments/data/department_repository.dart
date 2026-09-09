import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'department_api.dart';
import 'models/department.dart';

final departmentRepositoryProvider = Provider<DepartmentRepository>(
  (ref) => DepartmentRepository(ref.watch(departmentApiProvider)),
);

class DepartmentRepository {
  DepartmentRepository(this._api);

  final DepartmentApi _api;

  Future<List<Department>> list({int? schoolId}) async {
    try {
      final page = await _api.list(schoolId: schoolId);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<Department>> listPage({int? schoolId, required int page, required int perPage}) async {
    try {
      return await _api.list(schoolId: schoolId, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Department> create({int? schoolId, required String name, int? hodUserId}) async {
    try {
      return await _api.create(schoolId: schoolId, name: name, hodUserId: hodUserId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Department> update(int departmentId, {String? name, int? hodUserId}) async {
    try {
      return await _api.update(departmentId, name: name, hodUserId: hodUserId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int departmentId) async {
    try {
      await _api.delete(departmentId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
