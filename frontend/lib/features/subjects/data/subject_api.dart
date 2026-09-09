import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/subject.dart';

final subjectApiProvider = Provider<SubjectApi>((ref) => SubjectApi(ref.watch(dioClientProvider)));

class SubjectApi {
  SubjectApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<Subject>> list({int? schoolId, int? departmentId, int? page, int? perPage}) async {
    final response = await _dio.get(
      '/subjects',
      queryParameters: {'school_id': ?schoolId, 'department_id': ?departmentId, 'page': ?page, 'per_page': ?perPage},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Subject.fromJson);
  }

  Future<Subject> create({
    int? schoolId,
    required int departmentId,
    required String code,
    required String name,
    required int minClassLevel,
    required int maxClassLevel,
    int? leadTeacherId,
  }) async {
    final response = await _dio.post(
      '/subjects',
      data: {
        'school_id': schoolId,
        'department_id': departmentId,
        'code': code,
        'name': name,
        'min_class_level': minClassLevel,
        'max_class_level': maxClassLevel,
        'lead_teacher_id': leadTeacherId,
      },
    );

    return Subject.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Subject> update(
    int subjectId, {
    int? departmentId,
    String? code,
    String? name,
    int? minClassLevel,
    int? maxClassLevel,
    int? leadTeacherId,
  }) async {
    final response = await _dio.patch(
      '/subjects/$subjectId',
      data: {
        'department_id': ?departmentId,
        'code': ?code,
        'name': ?name,
        'min_class_level': ?minClassLevel,
        'max_class_level': ?maxClassLevel,
        'lead_teacher_id': leadTeacherId,
      },
    );

    return Subject.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int subjectId) async {
    await _dio.delete('/subjects/$subjectId');
  }
}
