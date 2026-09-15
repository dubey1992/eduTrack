import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../errors/failure.dart';
import 'auth_token_storage.dart';
import 'maintenance_notifier.dart';

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
      onError: (error, handler) {
        // A maintenance window is not this screen's failure, it is every
        // screen's. Recorded here, once, so the router can act on it rather
        // than each caller showing its own red box - see maintenanceProvider.
        if (error.response?.statusCode == 503) {
          ref.read(maintenanceProvider.notifier).reportUnavailable();
        }
        handler.next(error);
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
    // The backend always sends `details` as a JSON object, but this is a
    // system boundary - don't let an unexpected shape (e.g. a stray `[]`)
    // crash the app instead of just showing the message.
    final rawDetails = data['details'];
    final failure = Failure(
      code: data['code'] as String,
      message: data['message'] as String,
      details: rawDetails is Map<String, dynamic> ? rawDetails : const {},
    );

    // "The given data was invalid." tells the user nothing - surface the
    // first field message instead (the full map stays in details).
    final firstFieldMessage = failure.validationErrors.values.expand((m) => m).firstOrNull;
    if (failure.code == 'VALIDATION_ERROR' && firstFieldMessage != null) {
      return Failure(code: failure.code, message: firstFieldMessage, details: failure.details);
    }
    return failure;
  }

  return Failure.unknown(e.message);
}
