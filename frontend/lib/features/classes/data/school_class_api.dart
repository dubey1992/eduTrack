import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/school_class.dart';

final schoolClassApiProvider = Provider<SchoolClassApi>((ref) => SchoolClassApi(ref.watch(dioClientProvider)));

class SchoolClassApi {
  SchoolClassApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<SchoolClass>> list({int? schoolId, int? academicYearId, int? page, int? perPage}) async {
    final response = await _dio.get(
      '/classes',
      queryParameters: {
        'school_id': ?schoolId,
        'academic_year_id': ?academicYearId,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, SchoolClass.fromJson);
  }

  Future<SchoolClass> create({
    int? schoolId,
    required int academicYearId,
    required String name,
    required int level,
  }) async {
    final response = await _dio.post(
      '/classes',
      data: {'school_id': schoolId, 'academic_year_id': academicYearId, 'name': name, 'level': level},
    );

    return SchoolClass.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SchoolClass> update(int schoolClassId, {String? name, int? level}) async {
    final response = await _dio.patch('/classes/$schoolClassId', data: {'name': ?name, 'level': ?level});
    return SchoolClass.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int schoolClassId) async {
    await _dio.delete('/classes/$schoolClassId');
  }

  Future<ClassSection> addSection({
    required int schoolClassId,
    required String name,
    String? roomNumber,
    int? classTeacherId,
  }) async {
    final response = await _dio.post(
      '/classes/$schoolClassId/sections',
      data: {'name': name, 'room_number': roomNumber, 'class_teacher_id': classTeacherId},
    );

    return ClassSection.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ClassSection> updateSection(int sectionId, {String? name, String? roomNumber, int? classTeacherId}) async {
    final response = await _dio.patch(
      '/sections/$sectionId',
      data: {'name': ?name, 'room_number': roomNumber, 'class_teacher_id': classTeacherId},
    );

    return ClassSection.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteSection(int sectionId) async {
    await _dio.delete('/sections/$sectionId');
  }
}
