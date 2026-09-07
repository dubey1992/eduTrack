import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/dio_client.dart';
import 'models/app_user.dart';
import 'user_api.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(ref.watch(userApiProvider)));

class UserRepository {
  UserRepository(this._api);

  final UserApi _api;

  Future<List<AppUser>> list() async {
    try {
      final page = await _api.list();
      return page.items;
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
  }) async {
    try {
      return await _api.create(
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
