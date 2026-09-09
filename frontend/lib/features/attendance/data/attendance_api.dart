import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/attendance_record.dart';
import 'models/attendance_register.dart';

final attendanceApiProvider = Provider<AttendanceApi>((ref) => AttendanceApi(ref.watch(dioClientProvider)));

class AttendanceApi {
  AttendanceApi(this._dio);

  final Dio _dio;

  Future<AttendanceRegister> register({required int classSectionId, required String date}) async {
    final response = await _dio.get(
      '/attendance/register',
      queryParameters: {'class_section_id': classSectionId, 'date': date},
    );
    return AttendanceRegister.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AttendanceRegister> submit({
    required int classSectionId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    final response = await _dio.post(
      '/attendance',
      data: {'class_section_id': classSectionId, 'attendance_date': attendanceDate, 'records': records},
    );
    return AttendanceRegister.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AttendanceRegister> update({
    required int classSectionId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    final response = await _dio.patch(
      '/attendance',
      data: {'class_section_id': classSectionId, 'attendance_date': attendanceDate, 'records': records},
    );
    return AttendanceRegister.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<AttendanceRecord>> list({
    int? schoolId,
    int? classSectionId,
    int? studentId,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await _dio.get(
      '/attendance',
      queryParameters: {
        'school_id': ?schoolId,
        'class_section_id': ?classSectionId,
        'student_id': ?studentId,
        'status': ?status,
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, AttendanceRecord.fromJson);
  }
}
