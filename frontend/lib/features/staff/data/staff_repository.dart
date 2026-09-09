import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/staff_profile.dart';
import 'staff_api.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) => StaffRepository(ref.watch(staffApiProvider)));

class StaffRepository {
  StaffRepository(this._api);

  final StaffApi _api;

  Future<List<StaffProfile>> list({int? schoolId, int? departmentId, UserRole? role, String? search}) async {
    try {
      final page = await _api.list(schoolId: schoolId, departmentId: departmentId, role: role, search: search);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<StaffProfile>> listPage({
    int? schoolId,
    int? departmentId,
    UserRole? role,
    String? search,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(
        schoolId: schoolId,
        departmentId: departmentId,
        role: role,
        search: search,
        page: page,
        perPage: perPage,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
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
    try {
      return await _api.create(
        firstName: firstName,
        lastName: lastName,
        email: email,
        mobile: mobile,
        password: password,
        role: role,
        schoolId: schoolId,
        employeeId: employeeId,
        departmentId: departmentId,
        designation: designation,
        joiningDate: joiningDate,
        address: address,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<StaffProfile> update(
    int staffProfileId, {
    String? employeeId,
    int? departmentId,
    String? designation,
    DateTime? joiningDate,
    String? address,
  }) async {
    try {
      return await _api.update(
        staffProfileId,
        employeeId: employeeId,
        departmentId: departmentId,
        designation: designation,
        joiningDate: joiningDate,
        address: address,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
