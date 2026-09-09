import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/staff_attendance_record.dart';
import 'models/staff_attendance_register.dart';

final staffAttendanceApiProvider = Provider<StaffAttendanceApi>(
  (ref) => StaffAttendanceApi(ref.watch(dioClientProvider)),
);

class StaffAttendanceApi {
  StaffAttendanceApi(this._dio);

  final Dio _dio;

  Future<StaffAttendanceRegister> register({int? schoolId, int? departmentId, required String date}) async {
    final response = await _dio.get(
      '/staff-attendance/register',
      queryParameters: {'school_id': ?schoolId, 'department_id': ?departmentId, 'date': date},
    );
    return StaffAttendanceRegister.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StaffAttendanceRegister> submit({
    int? schoolId,
    int? departmentId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    final response = await _dio.post(
      '/staff-attendance',
      data: {
        'school_id': schoolId,
        'department_id': departmentId,
        'attendance_date': attendanceDate,
        'records': records,
      },
    );
    return StaffAttendanceRegister.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StaffAttendanceRegister> update({
    int? schoolId,
    int? departmentId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    final response = await _dio.patch(
      '/staff-attendance',
      data: {
        'school_id': schoolId,
        'department_id': departmentId,
        'attendance_date': attendanceDate,
        'records': records,
      },
    );
    return StaffAttendanceRegister.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<StaffAttendanceRecord>> list({
    int? schoolId,
    int? staffProfileId,
    int? departmentId,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await _dio.get(
      '/staff-attendance',
      queryParameters: {
        'school_id': ?schoolId,
        'staff_profile_id': ?staffProfileId,
        'department_id': ?departmentId,
        'status': ?status,
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, StaffAttendanceRecord.fromJson);
  }
}
