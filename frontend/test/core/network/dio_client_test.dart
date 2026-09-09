import 'package:dio/dio.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _exceptionWithResponseData(dynamic data) {
  final requestOptions = RequestOptions(path: '/auth/login');
  return DioException(
    requestOptions: requestOptions,
    response: Response(requestOptions: requestOptions, statusCode: 401, data: data),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  test('parses a well-formed error body into a Failure', () {
    final failure = failureFromDioException(
      _exceptionWithResponseData({
        'code': 'UNAUTHENTICATED',
        'message': 'These credentials do not match our records.',
        'details': <String, dynamic>{},
      }),
    );

    expect(failure.code, 'UNAUTHENTICATED');
    expect(failure.message, 'These credentials do not match our records.');
    expect(failure.details, <String, dynamic>{});
  });

  test('does not crash when details is a JSON array instead of an object', () {
    // Regression test: PHP's `[]` json_encodes as a JSON array, not an
    // object - a backend bug once sent `"details":[]` here, and casting
    // that straight to Map<String, dynamic> crashed every non-validation
    // error response app-wide (expired tokens, forbidden actions, 404s,
    // failed logins, ...). The backend is fixed, but this stays as a
    // system-boundary safety net - never trust the wire shape blindly.
    final failure = failureFromDioException(
      _exceptionWithResponseData({
        'code': 'UNAUTHENTICATED',
        'message': 'These credentials do not match our records.',
        'details': <dynamic>[],
      }),
    );

    expect(failure.code, 'UNAUTHENTICATED');
    expect(failure.message, 'These credentials do not match our records.');
    expect(failure.details, <String, dynamic>{});
  });

  test('falls back to Failure.network() on a connection error', () {
    final failure = failureFromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.connectionError,
      ),
    );

    expect(failure.code, 'NETWORK_ERROR');
  });

  test('falls back to Failure.unknown() when the body has no code/message', () {
    final failure = failureFromDioException(_exceptionWithResponseData('<html>502 Bad Gateway</html>'));

    expect(failure.code, 'UNKNOWN_ERROR');
  });
}
