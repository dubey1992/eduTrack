import 'package:dio/dio.dart';
import 'package:edutrack_app/core/network/connection_status.dart';
import 'package:edutrack_app/core/network/offline_copies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

/// The web app's kept copies of what its forms need (docs/offline-web.md,
/// O3), and the connection state (O1). A real Dio against an adapter that
/// answers or fails, so the interceptor runs as it does in the app.
class _Adapter implements HttpClientAdapter {
  bool online = true;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (!online) throw DioException.connectionError(requestOptions: options, reason: 'no route');
    return ResponseBody.fromString(
      '{"data": [{"id": 1, "name": "Grade 8"}], "at": $calls}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late InMemoryKeyValueStore store;
  late _Adapter adapter;
  late bool enabled;

  Dio dio() {
    final copies = OfflineCopies(store);
    final client = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = adapter;
    client.interceptors.add(OfflineCopiesInterceptor(() => copies, enabled: () => enabled));
    return client;
  }

  setUp(() {
    store = InMemoryKeyValueStore();
    adapter = _Adapter();
    enabled = true;
  });

  group('offline copies', () {
    test('an answer is kept, and served with its time when the server cannot be reached', () async {
      final client = dio();
      await client.get('/classes', queryParameters: {'school_id': 4});

      adapter.online = false;
      final response = await client.get('/classes', queryParameters: {'school_id': 4});

      expect(response.statusCode, 200);
      expect((response.data as Map)['at'], 1);
      expect(response.headers.value(OfflineCopiesInterceptor.header), isNotNull);
    });

    test('while online the server always answers - the copy is only refreshed', () async {
      final client = dio();
      await client.get('/classes');
      final second = await client.get('/classes');

      expect((second.data as Map)['at'], 2);
      expect(second.headers.value(OfflineCopiesInterceptor.header), isNull);
    });

    test('another query is another copy', () async {
      final client = dio();
      await client.get('/classes', queryParameters: {'school_id': 4});

      adapter.online = false;
      expect(() => client.get('/classes', queryParameters: {'school_id': 5}), throwsA(isA<DioException>()));
    });

    test('an address not on the list is never kept', () async {
      final client = dio();
      await client.get('/students');

      adapter.online = false;
      expect(() => client.get('/students'), throwsA(isA<DioException>()));
      expect(await store.read('offline.copies'), isNull);
    });

    test('nothing is kept or served when offline work is off (the phone apps)', () async {
      enabled = false;
      final client = dio();
      await client.get('/classes');

      adapter.online = false;
      expect(() => client.get('/classes'), throwsA(isA<DioException>()));
      expect(await store.read('offline.copies'), isNull);
    });

    test('clear() removes every copy - done at sign-out', () async {
      final client = dio();
      await client.get('/classes');
      await client.get('/timetable', queryParameters: {'teacher_id': 3});

      await OfflineCopies(store).clear();

      expect(store.values, isEmpty);
    });

    test('at most ${OfflineCopies.limit} copies, the oldest dropped first', () async {
      final client = dio();
      for (var i = 0; i <= OfflineCopies.limit; i++) {
        await client.get('/classes', queryParameters: {'page': i});
      }

      adapter.online = false;
      expect(() => client.get('/classes', queryParameters: {'page': 0}), throwsA(isA<DioException>()));
      expect((await client.get('/classes', queryParameters: {'page': OfflineCopies.limit})).statusCode, 200);
    });
  });

  group('connection status', () {
    test('offline, then online again announces the reconnection once', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final status = container.read(connectionStatusProvider.notifier);
      var reconnections = 0;
      final subscription = status.onReconnected.listen((_) => reconnections++);
      addTearDown(subscription.cancel);

      expect(container.read(connectionStatusProvider), isTrue);
      status.markOnline();
      status.markOffline();
      expect(container.read(connectionStatusProvider), isFalse);
      status.markOnline();
      status.markOnline();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(connectionStatusProvider), isTrue);
      expect(reconnections, 1);
    });
  });
}
