import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/authenticated_user.dart';

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(dioClientProvider)));

/// Thin wrapper around the /api/v1/auth/* and /api/v1/me endpoints. Holds no
/// state and no business logic - just HTTP calls (see backend CLAUDE.md
/// rule 7 layering: Presentation -> ViewModel -> Repository -> API Service).
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<(AuthenticatedUser, String)> login({required String email, required String password}) async {
    final response = await _dio.post('/auth/login', data: {'email': email, 'password': password});

    final user = AuthenticatedUser.fromJson(response.data['user'] as Map<String, dynamic>);
    final token = response.data['token'] as String;

    return (user, token);
  }

  Future<void> logout() => _dio.post('/auth/logout');

  Future<void> forgotPassword(String email) => _dio.post('/auth/forgot-password', data: {'email': email});

  Future<void> resetPassword({required String email, required String token, required String password}) {
    return _dio.post('/auth/reset-password', data: {'email': email, 'token': token, 'password': password});
  }

  Future<void> changePassword({required String currentPassword, required String password}) {
    return _dio.post(
      '/auth/change-password',
      data: {'current_password': currentPassword, 'password': password, 'password_confirmation': password},
    );
  }

  Future<AuthenticatedUser> me() async {
    final response = await _dio.get('/me');
    return AuthenticatedUser.fromJson(response.data as Map<String, dynamic>);
  }
}
