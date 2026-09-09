import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/app_user.dart';
import 'user_api.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(ref.watch(userApiProvider)));

class UserRepository {
  UserRepository(this._api);

  final UserApi _api;

  Future<List<AppUser>> list({List<UserRole>? roles, int? schoolId, String? status}) async {
    try {
      final page = await _api.list(roles: roles, schoolId: schoolId, status: status);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  /// The paginated variant used by the Users list screen - [list] above
  /// stays as-is for callers that want "every matching user" (e.g. the
  /// teacher picker), not one page of them.
  Future<PaginatedResponse<AppUser>> listPage({
    List<UserRole>? roles,
    int? schoolId,
    String? status,
    required int page,
    required int perPage,
  }) async {
    try {
      return await _api.list(roles: roles, schoolId: schoolId, status: status, page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AppUser> create({
    required String firstName,
    required String lastName,
    required String email,
    String? mobile,
    required String password,
    required UserRole role,
    int? schoolId,
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
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AppUser> update(
    int userId, {
    String? firstName,
    String? lastName,
    String? email,
    String? mobile,
    String? password,
    UserRole? role,
  }) async {
    try {
      return await _api.update(
        userId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        mobile: mobile,
        password: password,
        role: role,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AppUser> setActive(int userId, bool active) async {
    try {
      return active ? await _api.activate(userId) : await _api.deactivate(userId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
