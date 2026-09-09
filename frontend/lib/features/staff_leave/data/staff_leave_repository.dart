import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/leave_type.dart';
import 'models/staff_leave.dart';
import 'models/staff_leave_summary.dart';
import 'staff_leave_api.dart';

final staffLeaveRepositoryProvider = Provider<StaffLeaveRepository>(
  (ref) => StaffLeaveRepository(ref.watch(staffLeaveApiProvider)),
);

class StaffLeaveRepository {
  StaffLeaveRepository(this._api);

  final StaffLeaveApi _api;

  Future<StaffLeave> apply({
    required LeaveType leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    try {
      return await _api.apply(leaveType: leaveType, startDate: startDate, endDate: endDate, reason: reason);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<StaffLeave>> list({
    int? schoolId,
    int? departmentId,
    String? status,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(
        schoolId: schoolId,
        departmentId: departmentId,
        status: status,
        page: page,
        perPage: perPage,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<StaffLeaveSummary> summary({int? schoolId}) async {
    try {
      return await _api.summary(schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<StaffLeave> approve(int leaveId, {String? remarks}) async {
    try {
      return await _api.approve(leaveId, remarks: remarks);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<StaffLeave> reject(int leaveId, {String? remarks}) async {
    try {
      return await _api.reject(leaveId, remarks: remarks);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
