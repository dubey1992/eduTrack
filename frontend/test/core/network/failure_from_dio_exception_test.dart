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
}
