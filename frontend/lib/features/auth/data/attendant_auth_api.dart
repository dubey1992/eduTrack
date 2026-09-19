import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/authenticated_user.dart';

final attendantAuthApiProvider = Provider<AttendantAuthApi>((ref) => AttendantAuthApi(ref.watch(dioClientProvider)));

/// What a successful attendant sign-in answers: the session token, the
/// signed-in user and - on registration only - the device secret.
class AttendantSignIn {
  const AttendantSignIn({required this.user, required this.userJson, required this.token, this.deviceSecret});

  final AuthenticatedUser user;

  /// [user] as sent, kept on the phone for opening the app with no signal.
  final Map<String, dynamic> userJson;
  final String token;
  final String? deviceSecret;
}

/// The two public endpoints a bus attendant signs in through. Just HTTP.
class AttendantAuthApi {
  AttendantAuthApi(this._dio);

  final Dio _dio;

  Future<AttendantSignIn> setup({
    required String mobile,
    required String setupCode,
    required String passcode,
    required String deviceName,
  }) async {
    final response = await _dio.post(
      '/auth/attendant/setup',
      data: {'mobile': mobile, 'setup_code': setupCode, 'passcode': passcode, 'device_name': deviceName},
    );
    return _signInFrom(response.data as Map<String, dynamic>);
  }

  Future<AttendantSignIn> login({
    required String mobile,
    required String passcode,
    required String deviceSecret,
  }) async {
    final response = await _dio.post(
      '/auth/attendant/login',
      data: {'mobile': mobile, 'passcode': passcode, 'device_secret': deviceSecret},
    );
    return _signInFrom(response.data as Map<String, dynamic>);
  }

  AttendantSignIn _signInFrom(Map<String, dynamic> json) {
    final userJson = json['user'] as Map<String, dynamic>;
    return AttendantSignIn(
      user: AuthenticatedUser.fromJson(userJson),
      userJson: userJson,
      token: json['token'] as String,
      deviceSecret: json['device_secret'] as String?,
    );
  }
}
