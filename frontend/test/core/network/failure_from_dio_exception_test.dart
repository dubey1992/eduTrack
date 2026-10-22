import 'package:dio/dio.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _response(int status, Map<String, dynamic> body) {
  final options = RequestOptions(path: '/x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  test('a validation error surfaces the first field message, keeping the full map in details', () {
    final failure = failureFromDioException(
      _response(422, {
        'code': 'VALIDATION_ERROR',
        'message': 'The given data was invalid.',
        'details': {
          'errors': {
            'registration_number': ['The registration number has already been taken.'],
            'capacity': ['The capacity must not be greater than 200.'],
          },
        },
      }),
    );

    expect(failure.code, 'VALIDATION_ERROR');
    expect(failure.message, 'The registration number has already been taken.');
    expect(failure.validationErrors['capacity'], ['The capacity must not be greater than 200.']);
  });

  test('a validation error without field details keeps the generic message', () {
    final failure = failureFromDioException(
      _response(422, {'code': 'VALIDATION_ERROR', 'message': 'The given data was invalid.', 'details': {}}),
    );

    expect(failure.message, 'The given data was invalid.');
  });

  test('other business errors keep their own message', () {
    final failure = failureFromDioException(
      _response(409, {'code': 'ROUTE_CAPACITY_FULL', 'message': 'Bus 04 - Green Park is full.', 'details': {}}),
    );

    expect(failure.code, 'ROUTE_CAPACITY_FULL');
    expect(failure.message, 'Bus 04 - Green Park is full.');
  });

  test('a connection error maps to the network failure', () {
    final failure = failureFromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ),
    );

    expect(failure.code, 'NETWORK_ERROR');
  });

  group("a response that is not the app's error envelope", () {
    /// Found on a phone: a Django debug page came back as a 400 and the
    /// attendant's sign-in screen printed Dio's own explanation of itself,
    /// ending with "you have to fix the server code".
    test('never shows the user what Dio says about itself', () {
      final failure = failureFromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/auth/attendant/setup', method: 'POST'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/attendant/setup'),
            statusCode: 400,
            data: '<!DOCTYPE html><html><body>DisallowedHost</body></html>',
          ),
          message:
              'This exception was thrown because the response has a status code of 400 and '
              'RequestOptions.validateStatus was configured to throw for this status code.',
        ),
      );

      expect(failure.message, isNot(contains('validateStatus')));
      expect(failure.message, isNot(contains('status code')));
      expect(failure.message, isNot(contains('server code')));
      expect(failure.message, 'The server could not accept that. Please try again.');
    });

    test('says what the status means to the person holding the phone', () {
      String messageFor(int status) {
        return failureFromDioException(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            response: Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: status,
              data: '<html/>',
            ),
            message: 'Dio being explicit about itself',
          ),
        ).message;
      }

      expect(messageFor(401), 'Your session has ended. Sign in again.');
      expect(messageFor(403), 'You do not have permission to do that.');
      expect(messageFor(404), 'That is not there any more.');
      expect(messageFor(429), 'Too many tries. Wait a minute and try again.');
      expect(messageFor(502), 'The server had a problem. Please try again in a moment.');
    });

    test('and keeps the status where a developer can still find it', () {
      final failure = failureFromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 502,
            data: '<html/>',
          ),
        ),
      );

      expect(failure.code, 'UNKNOWN_ERROR');
      expect(failure.details['status'], 502);
    });

    test('with no response at all it stays general', () {
      final failure = failureFromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.unknown,
        ),
      );

      expect(failure.message, 'Something went wrong. Please try again.');
    });
  });
}
