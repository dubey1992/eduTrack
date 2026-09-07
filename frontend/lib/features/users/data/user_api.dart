import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/app_user.dart';

final userApiProvider = Provider<UserApi>((ref) => UserApi(ref.watch(dioClientProvider)));

class UserApi {
  UserApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<AppUser>> list() async {
    final response = await _dio.get('/users');
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, AppUser.fromJson);
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
    final response = await _dio.post(
      '/users',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'mobile': mobile,
        'password': password,
        'role': role.apiValue,
        'school_id': schoolId,
      },
    );

    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AppUser> activate(int userId) async {
    final response = await _dio.patch('/users/$userId/activate');
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AppUser> deactivate(int userId) async {
    final response = await _dio.patch('/users/$userId/deactivate');
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }
}
