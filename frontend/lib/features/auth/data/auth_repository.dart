import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/auth_token_storage.dart';
import '../../../core/network/dio_client.dart';
import 'attendant_device_storage.dart';
import 'auth_api.dart';
import 'models/authenticated_user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(authTokenStorageProvider),
    ref.watch(attendantDeviceStorageProvider),
  ),
);

/// Coordinates the auth API calls with on-device token persistence, and
/// converts transport-level errors into the app's [Failure] type so the
/// ViewModel never has to know about Dio.
class AuthRepository {
  AuthRepository(this._api, this._tokenStorage, [this._attendantStorage]);

  final AuthApi _api;
  final AuthTokenStorage _tokenStorage;

  /// Where a bus attendant's session is kept for opening the app with no
  /// signal. Null in tests that do not need it.
  final AttendantDeviceStorage? _attendantStorage;

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
      await _attendantStorage?.clearSession();
    }
  }

  /// Returns the current user if a stored token is still valid, or null if
  /// there is no session (no stored token, or the server rejected it).
  Future<AuthenticatedUser?> restoreSession() async {
    final token = await _tokenStorage.readToken();
    if (token == null) return null;

    try {
      final json = await _api.meJson();
      final user = AuthenticatedUser.fromJson(json);
      if (user.role == UserRole.busAttendant) await _attendantStorage?.saveSession(json);
      return user;
    } on DioException catch (e) {
      // A bus loses signal. An attendant opening the app there must still
      // reach the trip kept on the phone (docs/maps.md, "Offline"), so with
      // no answer at all their last session stands in until one comes.
      if (e.response == null) {
        final cached = await _attendantStorage?.readSession();
        if (cached != null) return AuthenticatedUser.fromJson(cached);
      }
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

  /// Changes the signed-in user's own password, and returns the session as
  /// it stands afterwards - which is how the "must change password" flag
  /// clears without a sign-out and back in.
  Future<AuthenticatedUser> changePassword({required String currentPassword, required String password}) async {
    try {
      await _api.changePassword(currentPassword: currentPassword, password: password);
      return await _api.me();
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
