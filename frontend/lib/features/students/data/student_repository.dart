import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/student.dart';
import 'models/student_enrollment.dart';
import 'student_api.dart';

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(ref.watch(studentApiProvider)),
);

class StudentRepository {
  StudentRepository(this._api);

  final StudentApi _api;

  Future<List<Student>> list({int? schoolId, int? classSectionId, String? search}) async {
    try {
      final page = await _api.list(schoolId: schoolId, classSectionId: classSectionId, search: search);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<Student>> listPage({
    int? schoolId,
    int? classSectionId,
    String? search,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(
        schoolId: schoolId,
        classSectionId: classSectionId,
        search: search,
        page: page,
        perPage: perPage,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Student> create({
    int? schoolId,
    required int classSectionId,
    required String admissionNumber,
    required String firstName,
    required String lastName,
    String? rollNumber,
    required String guardianName,
    String? guardianMobile,
    String? guardianEmail,
    String? studentMobile,
    String? studentEmail,
    String? address,
  }) async {
    try {
      return await _api.create(
        schoolId: schoolId,
        classSectionId: classSectionId,
        admissionNumber: admissionNumber,
        firstName: firstName,
        lastName: lastName,
        rollNumber: rollNumber,
        guardianName: guardianName,
        guardianMobile: guardianMobile,
        guardianEmail: guardianEmail,
        studentMobile: studentMobile,
        studentEmail: studentEmail,
        address: address,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Student> update(
    int studentId, {
    int? classSectionId,
    String? admissionNumber,
    String? firstName,
    String? lastName,
    String? rollNumber,
    String? guardianName,
    String? guardianMobile,
    String? guardianEmail,
    String? studentMobile,
    String? studentEmail,
    String? address,
  }) async {
    try {
      return await _api.update(
        studentId,
        classSectionId: classSectionId,
        admissionNumber: admissionNumber,
        firstName: firstName,
        lastName: lastName,
        rollNumber: rollNumber,
        guardianName: guardianName,
        guardianMobile: guardianMobile,
        guardianEmail: guardianEmail,
        studentMobile: studentMobile,
        studentEmail: studentEmail,
        address: address,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  /// [routeId] null clears the student's transport; otherwise assigns (or
  /// re-assigns) them to that route and stop.
  Future<Student> setTransport(int studentId, {required int? routeId, required int? stopId}) async {
    try {
      if (routeId == null || stopId == null) return await _api.unassignTransport(studentId);
      return await _api.assignTransport(studentId, routeId: routeId, stopId: stopId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Student> setActive(int studentId, bool active) async {
    try {
      return active ? await _api.activate(studentId) : await _api.deactivate(studentId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<List<StudentEnrollment>> enrollments(int studentId) async {
    try {
      return await _api.enrollments(studentId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
