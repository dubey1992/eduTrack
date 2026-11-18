import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/auth_token_storage.dart';
import '../../../core/network/dio_client.dart';
import 'family_auth_api.dart';
import 'family_device_storage.dart';
import 'family_saved_copies.dart';
import 'models/family_account.dart';

final familyAuthRepositoryProvider = Provider<FamilyAuthRepository>(
  (ref) => FamilyAuthRepository(
    ref.watch(familyAuthApiProvider),
    ref.watch(authTokenStorageProvider),
    ref.watch(familyDeviceStorageProvider),
    copies: ref.watch(familySavedCopiesProvider),
  ),
);

/// A parent's sign-in: registering this phone with the setup code from the
/// school's letter, then mobile + passcode on it. Built like the bus
/// attendant's (AttendantAuthRepository): the session token goes where every
/// app keeps it, the phone's registration beside it.
class FamilyAuthRepository {
  FamilyAuthRepository(this._api, this._tokenStorage, this._deviceStorage, {this.copies});

  /// Each screen's last answer, a child's records - forgotten on sign-out.
  final FamilySavedCopies? copies;

  /// The server's answer when this phone's secret does not match the number.
  static const deviceNotRegisteredCode = 'DEVICE_NOT_REGISTERED';

  final FamilyAuthApi _api;
  final AuthTokenStorage _tokenStorage;
  final FamilyDeviceStorage _deviceStorage;

  Future<FamilyDevice?> registeredDevice() => _deviceStorage.read();

  Future<String?> lastMobile() => _deviceStorage.readMobile();

  /// Registers this phone and signs in.
  Future<FamilyAccount> setup({required String mobile, required String setupCode, required String passcode}) async {
    final FamilySignIn signIn;
    try {
      signIn = await _api.setup(mobile: mobile, setupCode: setupCode, passcode: passcode, deviceName: _deviceName());
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }

    final secret = signIn.deviceSecret;
    if (secret == null || secret.isEmpty) {
      throw Failure.unknown('The school did not register this phone. Please try again.');
    }

    await _deviceStorage.save(FamilyDevice(mobile: mobile, secret: secret));
    await _deviceStorage.saveSession(signIn.accountJson);
    await _tokenStorage.saveToken(signIn.token);
    return signIn.account;
  }

  /// Signs in on a registered phone. When the server no longer knows this
  /// phone the secret is forgotten, so the next attempt asks for a new code.
  Future<FamilyAccount> login({required String mobile, required String passcode}) async {
    final device = await _deviceStorage.read();
    if (device == null) {
      throw const Failure(
        code: deviceNotRegisteredCode,
        message: 'This phone is not registered yet. Enter the setup code from your school\'s letter.',
      );
    }

    try {
      final signIn = await _api.login(mobile: mobile, passcode: passcode, deviceSecret: device.secret);
      await _deviceStorage.saveSession(signIn.accountJson);
      await _tokenStorage.saveToken(signIn.token);
      return signIn.account;
    } on DioException catch (e) {
      final failure = failureFromDioException(e);
      if (failure.code == deviceNotRegisteredCode) await _deviceStorage.forgetSecret();
      throw failure;
    }
  }

  /// Who this phone last saw signed in, without asking the server - so the
  /// app opens at once on a weak signal, as the staff app does. Null when
  /// nobody is signed in here.
  Future<FamilyAccount?> savedAccount() async {
    if (await _tokenStorage.readToken() == null) return null;

    final saved = await _deviceStorage.readSession();
    return saved == null ? null : FamilyAccount.fromJson(saved);
  }

  /// Who is signed in, from the server - or, with no signal, as the server
  /// last said. Null when nobody is.
  Future<FamilyAccount?> restore() async {
    final token = await _tokenStorage.readToken();
    if (token == null) return null;

    try {
      final json = await _api.me();
      await _deviceStorage.saveSession(json);
      return FamilyAccount.fromJson(json);
    } on DioException catch (e) {
      final failure = failureFromDioException(e);

      // No signal: open on what this phone last saw, and say so on screen.
      if (failure.code == Failure.network().code || failure.code == Failure.timeout().code) {
        final saved = await _deviceStorage.readSession();
        return saved == null ? null : FamilyAccount.fromJson(saved);
      }

      // The session is over, or the school switched the app off: signed out.
      await forgetSession();
      return null;
    }
  }

  /// Signs out of this session. The phone stays registered, so next time is
  /// mobile + passcode, not a new code.
  Future<void> logout() async {
    try {
      await _api.logout();
    } on DioException catch (e) {
      // Signed out on this phone whatever the server said; the session it
      // could not end expires on its own after 30 days unused.
      debugPrint('Could not end the session on the server: ${failureFromDioException(e).code}');
    }
    await forgetSession();
  }

  Future<void> forgetSession() async {
    await _tokenStorage.clearToken();
    await _deviceStorage.clearSession();
    try {
      await copies?.clear();
    } catch (error) {
      // Never blocks signing out.
      debugPrint('Saved screens could not be cleared on sign-out: $error');
    }
  }

  /// A name the school office sees in the parent's list of phones.
  String _deviceName() {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android phone',
      TargetPlatform.iOS => 'iPhone',
      _ => 'Computer',
    };
  }
}
