import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/school.dart';

final schoolApiProvider = Provider<SchoolApi>((ref) => SchoolApi(ref.watch(dioClientProvider)));

class SchoolApi {
  SchoolApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<School>> list() async {
    final response = await _dio.get('/schools');
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, School.fromJson);
  }

  Future<School> create(Map<String, dynamic> payload) async {
    final response = await _dio.post('/schools', data: payload);
    return School.fromJson(response.data as Map<String, dynamic>);
  }

  Future<School> update(int schoolId, Map<String, dynamic> payload) async {
    final response = await _dio.patch('/schools/$schoolId', data: payload);
    return School.fromJson(response.data as Map<String, dynamic>);
  }

  Future<School> activate(int schoolId) async {
    final response = await _dio.patch('/schools/$schoolId/activate');
    return School.fromJson(response.data as Map<String, dynamic>);
  }

  Future<School> deactivate(int schoolId) async {
    final response = await _dio.patch('/schools/$schoolId/deactivate');
    return School.fromJson(response.data as Map<String, dynamic>);
  }
}
