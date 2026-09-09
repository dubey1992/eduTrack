import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/subject.dart';
import 'subject_api.dart';

final subjectRepositoryProvider = Provider<SubjectRepository>(
  (ref) => SubjectRepository(ref.watch(subjectApiProvider)),
);

class SubjectRepository {
  SubjectRepository(this._api);

  final SubjectApi _api;

  Future<List<Subject>> list({int? schoolId, int? departmentId}) async {
    try {
      final page = await _api.list(schoolId: schoolId, departmentId: departmentId);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<Subject>> listPage({
    int? schoolId,
    int? departmentId,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(schoolId: schoolId, departmentId: departmentId, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
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
    try {
      return await _api.create(
        schoolId: schoolId,
        departmentId: departmentId,
        code: code,
        name: name,
        minClassLevel: minClassLevel,
        maxClassLevel: maxClassLevel,
        leadTeacherId: leadTeacherId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
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
    try {
      return await _api.update(
        subjectId,
        departmentId: departmentId,
        code: code,
        name: name,
        minClassLevel: minClassLevel,
        maxClassLevel: maxClassLevel,
        leadTeacherId: leadTeacherId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int subjectId) async {
    try {
      await _api.delete(subjectId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
