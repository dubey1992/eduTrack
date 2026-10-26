import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../errors/failure.dart';
import 'auth_token_storage.dart';
import 'maintenance_notifier.dart';
import 'session_ended_notifier.dart';

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
        // The same for a session the server no longer accepts: one answer
        // for the whole app, acted on by the auth notifier.
        if (endsSession(
          status: error.response?.statusCode,
          path: error.requestOptions.path,
          carriedSession: error.requestOptions.headers.containsKey('Authorization'),
        )) {
          ref.read(sessionEndedProvider.notifier).report();
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

  // Not the app's error envelope: a proxy's HTML page, a framework error
  // page, a gateway timeout. `e.message` here is Dio's own explanation of
  // itself - "This exception was thrown because the response has a status
  // code of 400 and RequestOptions.validateStatus was configured to throw"
  // - which a bus driver was shown on a phone, ending with "you have to
  // fix the server code". Never that. What the status means to the person
  // holding the phone, and the technical detail kept where a developer can
  // still find it.
  final status = e.response?.statusCode;

  developer.log(
    'Unrecognised error response',
    name: 'api',
    error: '${e.requestOptions.method} ${e.requestOptions.path} -> $status: ${e.message}',
  );

  return Failure(code: 'UNKNOWN_ERROR', message: _messageForStatus(status), details: {'status': ?status});
}

/// What a status code means to somebody who did not ask for one.
String _messageForStatus(int? status) {
  if (status == null) return 'Something went wrong. Please try again.';

  if (status == 401) return 'Your session has ended. Sign in again.';
  if (status == 403) return 'You do not have permission to do that.';
  if (status == 404) return 'That is not there any more.';
  if (status == 429) return 'Too many tries. Wait a minute and try again.';
  // A 4xx that did not come back in the app's own shape is a request this
  // build should not have made - there is nothing for the person to fix,
  // so do not imply there is.
  if (status < 500) return 'The server could not accept that. Please try again.';

  return 'The server had a problem. Please try again in a moment.';
}
