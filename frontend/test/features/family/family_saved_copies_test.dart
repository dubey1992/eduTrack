import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/family/application/family_offline.dart';
import 'package:edutrack_app/features/family/data/family_api.dart';
import 'package:edutrack_app/features/family/data/family_saved_copies.dart';
import 'package:edutrack_app/features/family/presentation/widgets/saved_copy_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

/// The network, played by a test: an answer, a refusal, or no signal.
class _Network implements HttpClientAdapter {
  Object? answer;
  int? status;
  bool signal = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!signal) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(
      jsonEncode(answer),
      status ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _fees = {
  'currency_code': 'INR',
  'totals': {'due': '3500.00', 'paid': '0.00', 'overdue': '0.00', 'balance': '3500.00'},
  'installments': <Object>[],
  'receipts': <Object>[],
};

/// Each Family screen's last answer, kept on the phone
/// (docs/mobile-apps-review.md, 2.2).
void main() {
  late _Network network;
  late FamilySavedCopies copies;
  late List<(String, DateTime?)> told;
  late FamilyApi api;

  setUp(() {
    network = _Network();
    copies = FamilySavedCopies(InMemoryKeyValueStore());
    told = [];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = network;
    api = FamilyApi(dio, copies: copies, onAnswer: (name, at) => told.add((name, at)));
  });

  test("an answer is kept, and the screen is told it is the server's", () async {
    network.answer = {'subjects': <Object>[]};

    await api.syllabus(12);

    expect(told.single, ('syllabus:12', null));
    expect((await copies.read('syllabus:12'))?.json, {'subjects': <Object>[]});
  });

  test('with no signal the saved copy is shown, and the screen is told from when', () async {
    network.answer = {'subjects': <Object>[]};
    await api.syllabus(12);
    network.signal = false;

    final subjects = await api.syllabus(12);

    expect(subjects, isEmpty);
    expect(told.last.$1, 'syllabus:12');
    expect(told.last.$2, isNotNull);
  });

  test('with no signal and nothing saved, it is the failure as before', () async {
    network.signal = false;

    expect(() => api.syllabus(12), throwsA(isA<DioException>()));
  });

  test("a refusal is the server's answer and is never covered by an old copy", () async {
    network.answer = {'subjects': <Object>[]};
    await api.syllabus(12);
    network
      ..answer = {'code': 'FORBIDDEN', 'message': 'No.'}
      ..status = 403;

    expect(() => api.syllabus(12), throwsA(isA<DioException>()));
  });

  test("each child's copy is its own", () async {
    network.answer = {'subjects': <Object>[]};
    await api.syllabus(12);
    network.signal = false;

    expect(() => api.syllabus(13), throwsA(isA<DioException>()));
  });

  test('signing out forgets every copy, Home included', () async {
    await copies.save('fees:12', _fees, DateTime(2026, 11, 18, 9, 40));
    final store = InMemoryKeyValueStore();
    final mine = FamilySavedCopies(store);
    await store.write('family_today_12', '{}');
    await mine.remember('family_today_12');
    await mine.save('fees:12', _fees, DateTime(2026, 11, 18));

    await mine.clear();

    expect(await mine.read('fees:12'), isNull);
    expect(await store.read('family_today_12'), isNull);
  });

  testWidgets('a screen showing a saved copy says from when, and nothing otherwise', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.familyLight(),
          home: const Scaffold(body: SavedCopyLine(name: 'fees:12')),
        ),
      ),
    );
    expect(find.textContaining('No connection'), findsNothing);

    container.read(familyOfflineProvider.notifier).old('fees:12', DateTime.now().copyWith(hour: 9, minute: 40));
    await tester.pump();
    expect(find.text('No connection. Showing what was true at 9:40 AM.'), findsOneWidget);

    container.read(familyOfflineProvider.notifier).fresh('fees:12');
    await tester.pump();
    expect(find.textContaining('No connection'), findsNothing);
  });
}
