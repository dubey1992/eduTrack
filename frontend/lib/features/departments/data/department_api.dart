import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/department.dart';

final departmentApiProvider = Provider<DepartmentApi>((ref) => DepartmentApi(ref.watch(dioClientProvider)));

class DepartmentApi {
  DepartmentApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<Department>> list({int? schoolId, int? page, int? perPage}) async {
    final response = await _dio.get(
      '/departments',
      queryParameters: {'school_id': ?schoolId, 'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Department.fromJson);
  }

  Future<Department> create({int? schoolId, required String name, int? hodUserId}) async {
    final response = await _dio.post(
      '/departments',
      data: {'school_id': schoolId, 'name': name, 'hod_user_id': hodUserId},
    );

    return Department.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Department> update(int departmentId, {String? name, int? hodUserId}) async {
    final response = await _dio.patch('/departments/$departmentId', data: {'name': ?name, 'hod_user_id': hodUserId});

    return Department.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int departmentId) async {
    await _dio.delete('/departments/$departmentId');
  }
}
