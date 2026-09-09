import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/school_class.dart';
import 'school_class_api.dart';

final schoolClassRepositoryProvider = Provider<SchoolClassRepository>(
  (ref) => SchoolClassRepository(ref.watch(schoolClassApiProvider)),
);

class SchoolClassRepository {
  SchoolClassRepository(this._api);

  final SchoolClassApi _api;

  Future<List<SchoolClass>> list({int? schoolId, int? academicYearId}) async {
    try {
      final page = await _api.list(schoolId: schoolId, academicYearId: academicYearId);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<SchoolClass>> listPage({
    int? schoolId,
    int? academicYearId,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(schoolId: schoolId, academicYearId: academicYearId, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SchoolClass> create({
    int? schoolId,
    required int academicYearId,
    required String name,
    required int level,
  }) async {
    try {
      return await _api.create(schoolId: schoolId, academicYearId: academicYearId, name: name, level: level);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<SchoolClass> update(int schoolClassId, {String? name, int? level}) async {
    try {
      return await _api.update(schoolClassId, name: name, level: level);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> delete(int schoolClassId) async {
    try {
      await _api.delete(schoolClassId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<ClassSection> addSection({
    required int schoolClassId,
    required String name,
    String? roomNumber,
    int? classTeacherId,
  }) async {
    try {
      return await _api.addSection(
        schoolClassId: schoolClassId,
        name: name,
        roomNumber: roomNumber,
        classTeacherId: classTeacherId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<ClassSection> updateSection(int sectionId, {String? name, String? roomNumber, int? classTeacherId}) async {
    try {
      return await _api.updateSection(sectionId, name: name, roomNumber: roomNumber, classTeacherId: classTeacherId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> deleteSection(int sectionId) async {
    try {
      await _api.deleteSection(sectionId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
