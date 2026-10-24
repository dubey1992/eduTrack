import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/attendant_access.dart';
import 'models/staff_profile.dart';

final staffApiProvider = Provider<StaffApi>((ref) => StaffApi(ref.watch(dioClientProvider)));

class StaffApi {
  StaffApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<StaffProfile>> list({
    int? schoolId,
    int? departmentId,
    UserRole? role,
    List<UserRole>? roles,
    String? search,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/staff',
      queryParameters: {
        'school_id': ?schoolId,
        'department_id': ?departmentId,
        // One role, or several: the Crew screen asks for drivers and
        // attendants in one page, and the server takes a comma-separated list.
        'role': ?(roles != null ? roles.map((r) => r.apiValue).join(',') : role?.apiValue),
        'search': ?search,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, StaffProfile.fromJson);
  }

  /// [email] and [password] may be null for a Bus Attendant only: they sign
  /// in with their mobile number and a passcode, and the server stores a
  /// placeholder address when none is given.
  Future<StaffProfile> create({
    required String firstName,
    required String lastName,
    String? email,
    String? mobile,
    String? password,
    required UserRole role,
    int? schoolId,
    required String employeeId,
    String? biometricUserId,
    int? departmentId,
    String? designation,
    required DateTime joiningDate,
    String? address,
    String? licenceNumber,
    DateTime? licenceExpiry,
  }) async {
    final response = await _dio.post(
      '/staff',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'mobile': mobile,
        'password': ?password,
        'role': role.apiValue,
        'school_id': schoolId,
        'employee_id': employeeId,
        'biometric_user_id': biometricUserId,
        'department_id': departmentId,
        'designation': designation,
        'joining_date': DateFormat('yyyy-MM-dd').format(joiningDate),
        'address': address,
        // A driver's licence; the server ignores it for anybody else.
        'licence_number': ?licenceNumber,
        'licence_expiry': ?(licenceExpiry == null ? null : DateFormat('yyyy-MM-dd').format(licenceExpiry)),
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
    bool licenceGiven = false,
    String? licenceNumber,
    DateTime? licenceExpiry,
  }) async {
    final response = await _dio.patch(
      '/staff/$staffProfileId',
      data: {
        'employee_id': ?employeeId,
        'department_id': departmentId,
        'designation': designation,
        if (joiningDate != null) 'joining_date': DateFormat('yyyy-MM-dd').format(joiningDate),
        'address': address,
        // Only when the form had licence fields - a driver's. Sent as a
        // pair so clearing the expiry reaches the server as null.
        if (licenceGiven) 'licence_number': licenceNumber,
        if (licenceGiven)
          'licence_expiry': licenceExpiry == null ? null : DateFormat('yyyy-MM-dd').format(licenceExpiry),
      },
    );

    return StaffProfile.fromJson(response.data as Map<String, dynamic>);
  }

  // ── a Bus Attendant's sign-in ─────────────────────────────────────────

  Future<AttendantAccess> attendantAccess(int staffProfileId) async {
    final response = await _dio.get('/staff/$staffProfileId/attendant');
    return AttendantAccess.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AttendantSetupCode> issueSetupCode(int staffProfileId) async {
    final response = await _dio.post('/staff/$staffProfileId/attendant/setup-code');
    return AttendantSetupCode.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AttendantAccess> removeAttendantDevice(int staffProfileId, int deviceId) async {
    final response = await _dio.delete('/staff/$staffProfileId/attendant/devices/$deviceId');
    return AttendantAccess.fromJson(response.data as Map<String, dynamic>);
  }
}
