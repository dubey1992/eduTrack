import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/auth_token_storage.dart';
import '../../../core/network/dio_client.dart';
import 'attendant_auth_api.dart';
import 'attendant_device_storage.dart';
import 'models/authenticated_user.dart';

final attendantAuthRepositoryProvider = Provider<AttendantAuthRepository>(
  (ref) => AttendantAuthRepository(
    ref.watch(attendantAuthApiProvider),
    ref.watch(authTokenStorageProvider),
    ref.watch(attendantDeviceStorageProvider),
  ),
);

/// A bus attendant's sign-in: registering this phone with a setup code, then
/// mobile + passcode on it. Stores the session token where the email sign-in
/// does, and the device registration beside it.
class AttendantAuthRepository {
  AttendantAuthRepository(this._api, this._tokenStorage, this._deviceStorage);

  /// The server's answer when this phone's secret does not match the number.
  static const deviceNotRegisteredCode = 'DEVICE_NOT_REGISTERED';

  final AttendantAuthApi _api;
  final AuthTokenStorage _tokenStorage;
  final AttendantDeviceStorage _deviceStorage;

  /// This phone's registration, or null when it has none.
  Future<AttendantDevice?> registeredDevice() => _deviceStorage.read();

  /// The mobile number last used on this phone, if any.
  Future<String?> lastMobile() => _deviceStorage.readMobile();

  /// Registers this phone and signs in.
  Future<AuthenticatedUser> setup({required String mobile, required String setupCode, required String passcode}) async {
    final AttendantSignIn signIn;
    try {
      signIn = await _api.setup(mobile: mobile, setupCode: setupCode, passcode: passcode, deviceName: _deviceName());
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }

    final secret = signIn.deviceSecret;
    if (secret == null || secret.isEmpty) {
      throw Failure.unknown('The server did not register this phone. Please try again.');
    }

    await _deviceStorage.save(AttendantDevice(mobile: mobile, secret: secret));
    await _deviceStorage.saveSession(signIn.userJson);
    await _tokenStorage.saveToken(signIn.token);
    return signIn.user;
  }

  /// Signs in on a registered phone. When the server no longer knows this
  /// phone the secret is forgotten, so the next attempt asks for a setup code.
  Future<AuthenticatedUser> login({required String mobile, required String passcode}) async {
    final device = await _deviceStorage.read();
    if (device == null) {
      throw const Failure(
        code: deviceNotRegisteredCode,
        message: 'This phone is not registered yet. Enter the setup code from your school office.',
      );
    }

    try {
      final signIn = await _api.login(mobile: mobile, passcode: passcode, deviceSecret: device.secret);
      await _deviceStorage.saveSession(signIn.userJson);
      await _tokenStorage.saveToken(signIn.token);
      return signIn.user;
    } on DioException catch (e) {
      final failure = failureFromDioException(e);
      if (failure.code == deviceNotRegisteredCode) await _deviceStorage.forgetSecret();
      throw failure;
    }
  }

  /// A name the office sees in the attendant's device list.
  String _deviceName() {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android phone',
      TargetPlatform.iOS => 'iPhone',
      _ => 'Computer',
    };
  }
}
