import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:edutrack_app/core/network/retry_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers each request from a script: a status and body per try, or a
/// dropped connection.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<Object> script;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final step = script[calls < script.length ? calls : script.length - 1];
    calls++;

    if (step == _drop) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'XMLHttpRequest error',
      );
    }

    final (status, body, type) = step as (int, String, String);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [type],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _drop = 'drop';
const _ok = (200, '{"data":[]}', 'application/json');
const _hostPage = (500, '<html><title>500 Internal Server Error</title></html>', 'text/html');
const _apiError = (500, '{"code":"SERVER_ERROR","message":"Broken.","details":{}}', 'application/json');

(Dio, _ScriptedAdapter) _client(List<Object> script) {
  final adapter = _ScriptedAdapter(script);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))..httpClientAdapter = adapter;
  dio.interceptors.add(TransientRetryInterceptor(dio, delays: const [Duration.zero, Duration.zero]));

  return (dio, adapter);
}

void main() {
  test("a read the host turned away is tried again and succeeds", () async {
    final (dio, adapter) = _client([_hostPage, _ok]);

    final response = await dio.get<dynamic>('/dashboard');

    expect(response.statusCode, 200);
    expect(adapter.calls, 2);
  });

  test('a dropped connection is tried again too', () async {
    final (dio, adapter) = _client([_drop, _drop, _ok]);

    final response = await dio.get<dynamic>('/me');

    expect(jsonEncode(response.data), '{"data":[]}');
    expect(adapter.calls, 3);
  });

  test('it gives up after two more tries and reports the last failure', () async {
    final (dio, adapter) = _client([_drop]);

    await expectLater(dio.get<dynamic>('/me'), throwsA(isA<DioException>()));
    expect(adapter.calls, 3);
  });

  test('a write is never sent twice', () async {
    final (dio, adapter) = _client([_drop, _ok]);

    await expectLater(dio.post<dynamic>('/fees/receipts', data: {'amount': '100.00'}), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test("the API's own error is an answer, not a blip", () async {
    final (dio, adapter) = _client([_apiError, _ok]);

    await expectLater(dio.get<dynamic>('/reports/fee-collection'), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test('maintenance and refusals are not retried', () async {
    for (final status in [503, 401, 403, 404, 422]) {
      final (dio, adapter) = _client([(status, '<html></html>', 'text/html'), _ok]);

      await expectLater(dio.get<dynamic>('/dashboard'), throwsA(isA<DioException>()), reason: '$status');
      expect(adapter.calls, 1, reason: '$status');
    }
  });
}
