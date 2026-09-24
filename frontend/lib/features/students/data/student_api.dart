import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/student.dart';
import 'models/student_enrollment.dart';

final studentApiProvider = Provider<StudentApi>((ref) => StudentApi(ref.watch(dioClientProvider)));

class StudentApi {
  StudentApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<Student>> list({
    int? schoolId,
    int? classSectionId,
    String? search,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/students',
      queryParameters: {
        'school_id': ?schoolId,
        'class_section_id': ?classSectionId,
        'search': ?search,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Student.fromJson);
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
    final response = await _dio.post(
      '/students',
      data: {
        'school_id': schoolId,
        'class_section_id': classSectionId,
        'admission_number': admissionNumber,
        'first_name': firstName,
        'last_name': lastName,
        'roll_number': rollNumber,
        'guardian_name': guardianName,
        'guardian_mobile': guardianMobile,
        'guardian_email': guardianEmail,
        'student_mobile': studentMobile,
        'student_email': studentEmail,
        'address': address,
      },
    );

    return Student.fromJson(response.data as Map<String, dynamic>);
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
    final response = await _dio.patch(
      '/students/$studentId',
      data: {
        'class_section_id': classSectionId,
        'admission_number': ?admissionNumber,
        'first_name': ?firstName,
        'last_name': ?lastName,
        'roll_number': rollNumber,
        'guardian_name': ?guardianName,
        'guardian_mobile': guardianMobile,
        'guardian_email': guardianEmail,
        'student_mobile': studentMobile,
        'student_email': studentEmail,
        'address': address,
      },
    );

    return Student.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Student> assignTransport(int studentId, {required int routeId, required int stopId}) async {
    final response = await _dio.put(
      '/students/$studentId/transport',
      data: {'route_id': routeId, 'transport_stop_id': stopId},
    );
    return Student.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Student> unassignTransport(int studentId) async {
    final response = await _dio.delete('/students/$studentId/transport');
    return Student.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Student> activate(int studentId) async {
    final response = await _dio.patch('/students/$studentId/activate');
    return Student.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Student> deactivate(int studentId) async {
    final response = await _dio.patch('/students/$studentId/deactivate');
    return Student.fromJson(response.data as Map<String, dynamic>);
  }

  /// A student's year-by-year history. A plain list, not a page: it holds one
  /// row per academic year the school has run.
  Future<List<StudentEnrollment>> enrollments(int studentId) async {
    final response = await _dio.get('/students/$studentId/enrollments');

    return [for (final row in response.data as List<dynamic>) StudentEnrollment.fromJson(row as Map<String, dynamic>)];
  }
}
