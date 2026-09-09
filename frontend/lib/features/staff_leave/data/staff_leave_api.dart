import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/leave_type.dart';
import 'models/staff_leave.dart';
import 'models/staff_leave_summary.dart';

final staffLeaveApiProvider = Provider<StaffLeaveApi>((ref) => StaffLeaveApi(ref.watch(dioClientProvider)));

class StaffLeaveApi {
  StaffLeaveApi(this._dio);

  final Dio _dio;

  Future<StaffLeave> apply({
    required LeaveType leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    final response = await _dio.post(
      '/leaves',
      data: {'leave_type': leaveType.apiValue, 'start_date': startDate, 'end_date': endDate, 'reason': reason},
    );
    return StaffLeave.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<StaffLeave>> list({
    int? schoolId,
    int? departmentId,
    String? status,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/leaves',
      queryParameters: {
        'school_id': ?schoolId,
        'department_id': ?departmentId,
        'status': ?status,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, StaffLeave.fromJson);
  }

  Future<StaffLeaveSummary> summary({int? schoolId}) async {
    final response = await _dio.get('/leaves/summary', queryParameters: {'school_id': ?schoolId});
    return StaffLeaveSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StaffLeave> approve(int leaveId, {String? remarks}) async {
    final response = await _dio.patch('/leaves/$leaveId/approve', data: {'remarks': remarks});
    return StaffLeave.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StaffLeave> reject(int leaveId, {String? remarks}) async {
    final response = await _dio.patch('/leaves/$leaveId/reject', data: {'remarks': remarks});
    return StaffLeave.fromJson(response.data as Map<String, dynamic>);
  }
}
