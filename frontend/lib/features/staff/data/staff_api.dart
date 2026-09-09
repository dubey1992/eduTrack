import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/staff_profile.dart';

final staffApiProvider = Provider<StaffApi>((ref) => StaffApi(ref.watch(dioClientProvider)));

class StaffApi {
  StaffApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<StaffProfile>> list({
    int? schoolId,
    int? departmentId,
    UserRole? role,
    String? search,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/staff',
      queryParameters: {
        'school_id': ?schoolId,
        'department_id': ?departmentId,
        'role': ?role?.apiValue,
        'search': ?search,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, StaffProfile.fromJson);
  }

  Future<StaffProfile> create({
    required String firstName,
    required String lastName,
    required String email,
    String? mobile,
    required String password,
    required UserRole role,
    int? schoolId,
    required String employeeId,
    int? departmentId,
    String? designation,
    required DateTime joiningDate,
    String? address,
  }) async {
    final response = await _dio.post(
      '/staff',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'mobile': mobile,
        'password': password,
        'role': role.apiValue,
        'school_id': schoolId,
        'employee_id': employeeId,
        'department_id': departmentId,
        'designation': designation,
        'joining_date': DateFormat('yyyy-MM-dd').format(joiningDate),
        'address': address,
      },
    );

    return StaffProfile.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StaffProfile> update(
    int staffProfileId, {
    String? employeeId,
    int? departmentId,
    String? designation,
    DateTime? joiningDate,
    String? address,
  }) async {
    final response = await _dio.patch(
      '/staff/$staffProfileId',
      data: {
        'employee_id': ?employeeId,
        'department_id': departmentId,
        'designation': designation,
        if (joiningDate != null) 'joining_date': DateFormat('yyyy-MM-dd').format(joiningDate),
        'address': address,
      },
    );

    return StaffProfile.fromJson(response.data as Map<String, dynamic>);
  }
}
