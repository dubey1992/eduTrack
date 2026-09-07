import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../errors/failure.dart';
import 'auth_token_storage.dart';

final authTokenStorageProvider = Provider<AuthTokenStorage>((ref) => AuthTokenStorage());

/// Shared Dio client: attaches the bearer token to every request and maps
/// every failure response to the app's standard [Failure] shape so callers
/// never need to parse raw DioException/response bodies themselves.
final dioClientProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(authTokenStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      headers: {'Accept': 'application/json'},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokenStorage.readToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );

  return dio;
});

/// Converts a [DioException] into the app's standard [Failure] type.
Failure failureFromDioException(DioException e) {
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return Failure.network();
  }

  final data = e.response?.data;
  if (data is Map<String, dynamic> && data['code'] is String && data['message'] is String) {
    return Failure(
      code: data['code'] as String,
      message: data['message'] as String,
      details: (data['details'] as Map<String, dynamic>?) ?? const {},
    );
  }

  return Failure.unknown(e.message);
}
