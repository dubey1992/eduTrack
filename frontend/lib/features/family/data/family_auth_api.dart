import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/family_account.dart';

final familyAuthApiProvider = Provider<FamilyAuthApi>((ref) => FamilyAuthApi(ref.watch(dioClientProvider)));

/// What a successful sign-in answers: the session token, the account as
/// sent (kept for opening the app with no signal) and - on registering a
/// phone only - the device secret.
class FamilySignIn {
  const FamilySignIn({required this.account, required this.accountJson, required this.token, this.deviceSecret});

  final FamilyAccount account;
  final Map<String, dynamic> accountJson;
  final String token;
  final String? deviceSecret;
}

/// The Family app's sign-in endpoints (school/views/family.py). Just HTTP.
class FamilyAuthApi {
  FamilyAuthApi(this._dio);

  final Dio _dio;

  Future<FamilySignIn> setup({
    required String mobile,
    required String setupCode,
    required String passcode,
    required String deviceName,
  }) async {
    final response = await _dio.post(
      '/family/auth/setup',
      data: {'mobile': mobile, 'setup_code': setupCode, 'passcode': passcode, 'device_name': deviceName},
    );
    return _signInFrom(response.data as Map<String, dynamic>);
  }

  Future<FamilySignIn> login({required String mobile, required String passcode, required String deviceSecret}) async {
    final response = await _dio.post(
      '/family/auth/login',
      data: {'mobile': mobile, 'passcode': passcode, 'device_secret': deviceSecret},
    );
    return _signInFrom(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/family/me');
    return response.data as Map<String, dynamic>;
  }

  Future<void> logout() => _dio.post('/family/auth/logout');

  FamilySignIn _signInFrom(Map<String, dynamic> json) {
    final accountJson = json['me'] as Map<String, dynamic>;
    return FamilySignIn(
      account: FamilyAccount.fromJson(accountJson),
      accountJson: accountJson,
      token: json['token'] as String,
      deviceSecret: json['device_secret'] as String?,
    );
  }
}
