import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) => DeviceRepository(ref.watch(dioClientProvider)));

/// The phones a person is signed in on, for push (docs/teacher-app.md, T6).
class DeviceRepository {
  DeviceRepository(this._dio);

  final Dio _dio;

  /// Tells the server this install of the app belongs to the signed-in
  /// person. Throws the server's Failure.
  Future<void> register(String token, {required String app}) async {
    try {
      await _dio.post('/devices', data: {'token': token, 'platform': platformName, 'app': app});
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  /// Takes this install off the signed-in person, at sign-out.
  Future<void> forget(String token) async {
    try {
      await _dio.delete('/devices', data: {'token': token});
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  static String get platformName => switch (defaultTargetPlatform) {
    _ when kIsWeb => 'web',
    TargetPlatform.iOS => 'ios',
    _ => 'android',
  };
}

/// The token this install registered, kept so sign-out can take it back.
class PushRegistration {
  PushRegistration(this._ref);

  final Ref _ref;
  String? _token;

  String? get token => _token;

  Future<void> register(String token, {required String app}) async {
    await _ref.read(deviceRepositoryProvider).register(token, app: app);
    _token = token;
  }

  /// Forgets this phone on the server. Never stands in the way of signing
  /// out: without signal the server keeps the row until Firebase says the
  /// token is dead, or somebody else signs in on the phone and takes it.
  Future<void> forget() async {
    final token = _token;
    _token = null;
    if (token == null) return;

    try {
      await _ref.read(deviceRepositoryProvider).forget(token);
    } catch (error) {
      debugPrint('Could not forget this phone for push: $error');
    }
  }
}

final pushRegistrationProvider = Provider<PushRegistration>(PushRegistration.new);
