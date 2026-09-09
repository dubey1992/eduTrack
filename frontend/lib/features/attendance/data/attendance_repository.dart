import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'attendance_api.dart';
import 'models/attendance_record.dart';
import 'models/attendance_register.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(attendanceApiProvider)),
);

class AttendanceRepository {
  AttendanceRepository(this._api);

  final AttendanceApi _api;

  Future<AttendanceRegister> register({required int classSectionId, required String date}) async {
    try {
      return await _api.register(classSectionId: classSectionId, date: date);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AttendanceRegister> submit({
    required int classSectionId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    try {
      return await _api.submit(classSectionId: classSectionId, attendanceDate: attendanceDate, records: records);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AttendanceRegister> update({
    required int classSectionId,
    required String attendanceDate,
    required List<Map<String, dynamic>> records,
  }) async {
    try {
      return await _api.update(classSectionId: classSectionId, attendanceDate: attendanceDate, records: records);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<List<AttendanceRecord>> list({
    int? schoolId,
    int? classSectionId,
    int? studentId,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final page = await _api.list(
        schoolId: schoolId,
        classSectionId: classSectionId,
        studentId: studentId,
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
