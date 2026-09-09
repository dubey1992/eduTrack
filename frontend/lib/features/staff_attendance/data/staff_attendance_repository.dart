import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/staff_attendance_record.dart';
import 'models/staff_attendance_register.dart';
import 'staff_attendance_api.dart';

final staffAttendanceRepositoryProvider = Provider<StaffAttendanceRepository>(
  (ref) => StaffAttendanceRepository(ref.watch(staffAttendanceApiProvider)),
);

class StaffAttendanceRepository {
  StaffAttendanceRepository(this._api);

  final StaffAttendanceApi _api;

  Future<StaffAttendanceRegister> register({int? schoolId, int? departmentId, required String date}) async {
    try {
      return await _api.register(schoolId: schoolId, departmentId: departmentId, date: date);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<StaffAttendanceRegister> submit({
    int? schoolId,
    int? departmentId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    try {
      return await _api.submit(
        schoolId: schoolId,
        departmentId: departmentId,
        attendanceDate: attendanceDate,
        records: records,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<StaffAttendanceRegister> update({
    int? schoolId,
    int? departmentId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    try {
      return await _api.update(
        schoolId: schoolId,
        departmentId: departmentId,
        attendanceDate: attendanceDate,
        records: records,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<List<StaffAttendanceRecord>> list({
    int? schoolId,
    int? staffProfileId,
    int? departmentId,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final page = await _api.list(
        schoolId: schoolId,
        staffProfileId: staffProfileId,
        departmentId: departmentId,
        status: status,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
