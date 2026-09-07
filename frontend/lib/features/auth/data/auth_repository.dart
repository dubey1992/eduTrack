import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_token_storage.dart';
import '../../../core/network/dio_client.dart';
import 'auth_api.dart';
import 'models/authenticated_user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(authApiProvider), ref.watch(authTokenStorageProvider)),
);

/// Coordinates the auth API calls with on-device token persistence, and
/// converts transport-level errors into the app's [Failure] type so the
/// ViewModel never has to know about Dio.
class AuthRepository {
  AuthRepository(this._api, this._tokenStorage);

  final AuthApi _api;
  final AuthTokenStorage _tokenStorage;

  Future<AuthenticatedUser> login({required String email, required String password}) async {
    try {
      final (user, token) = await _api.login(email: email, password: password);
      await _tokenStorage.saveToken(token);
      return user;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } on DioException catch (_) {
      // Even if the server call fails (e.g. token already expired), the
      // device should still forget the token so the user is logged out.
    } finally {
      await _tokenStorage.clearToken();
    }
  }

  /// Returns the current user if a stored token is still valid, or null if
  /// there is no session (no stored token, or the server rejected it).
  Future<AuthenticatedUser?> restoreSession() async {
    final token = await _tokenStorage.readToken();
    if (token == null) return null;

    try {
      return await _api.me();
    } on DioException catch (_) {
      await _tokenStorage.clearToken();
      return null;
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _api.forgotPassword(email);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> resetPassword({required String email, required String token, required String password}) async {
    try {
      await _api.resetPassword(email: email, token: token, password: password);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
