import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/key_value_store.dart';

/// The last answer to a few read-only requests the web app's forms need
/// before they can be filled in - the class list above all - kept on the
/// computer so the form still opens when the school's internet is down
/// (docs/offline-web.md, O3).
///
/// Used only when a request cannot reach the server; while online every
/// request goes to the server exactly as before and the copy is refreshed.
/// A short list of addresses, not the whole API: records are not mirrored
/// here (that would be O2, not built). Cleared at sign-out with the
/// session, and the web app only - the phone apps keep their own copies.
class OfflineCopies {
  OfflineCopies(this._store);

  final KeyValueStore _store;

  /// The read-only addresses worth keeping, by path.
  static final kept = [
    // The class picker on the register, the marks sheet and notices.
    RegExp(r'^/classes$'),
    // A test's marks sheet, so marks can be entered offline and sent later.
    RegExp(r'^/assessments/\d+/marks$'),
    // The teaching reports page: the teacher's periods, the reports filed
    // and the day's summary, so a report can be written offline.
    RegExp(r'^/timetable$'),
    RegExp(r'^/teaching-reports$'),
    RegExp(r'^/teaching-reports/summary$'),
    // The office's staff register for a day it has already opened.
    RegExp(r'^/staff-attendance/register$'),
  ];

  /// Most copies kept; the oldest goes first.
  static const limit = 40;

  static const _indexKey = 'offline.copies';
  static String _key(String id) => 'offline.copy.$id';

  static bool keeps(RequestOptions options) =>
      options.method == 'GET' && kept.any((pattern) => pattern.hasMatch(options.path));

  /// The path and its query, in a stable order, as the copy's name.
  static String idOf(RequestOptions options) {
    final query = options.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return [options.path, for (final entry in query) '${entry.key}=${entry.value}'].join('|');
  }

  Future<void> save(RequestOptions options, Object? data) async {
    final id = idOf(options);
    await _store.write(_key(id), jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'data': data}));
    final index = [
      for (final other in await _index())
        if (other != id) other,
      id,
    ];
    while (index.length > limit) {
      await _store.delete(_key(index.removeAt(0)));
    }
    await _store.write(_indexKey, jsonEncode(index));
  }

  /// The kept answer and when it was kept, or null.
  Future<({Object? data, DateTime savedAt})?> read(RequestOptions options) async {
    final raw = await _store.read(_key(idOf(options)));
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (data: json['data'], savedAt: DateTime.parse(json['saved_at'] as String));
  }

  Future<void> clear() async {
    for (final id in await _index()) {
      await _store.delete(_key(id));
    }
    await _store.delete(_indexKey);
  }

  Future<List<String>> _index() async {
    final raw = await _store.read(_indexKey);
    return raw == null ? <String>[] : [for (final id in jsonDecode(raw) as List<dynamic>) id as String];
  }
}

final offlineCopiesProvider = Provider<OfflineCopies>((ref) => OfflineCopies(ref.watch(keyValueStoreProvider)));

/// Keeps and serves [OfflineCopies]. Answers with a kept copy only when the
/// request could not reach the server; a response then carries the header
/// `x-offline-copy` with when it was kept.
class OfflineCopiesInterceptor extends Interceptor {
  OfflineCopiesInterceptor(this._copies, {required this.enabled});

  final OfflineCopies Function() _copies;

  /// Asked on each request: the web app only (offlineWorkProvider).
  final bool Function() enabled;

  static const header = 'x-offline-copy';

  @override
  Future<void> onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    if (enabled() && OfflineCopies.keeps(response.requestOptions) && response.statusCode == 200) {
      try {
        await _copies().save(response.requestOptions, response.data);
      } catch (error) {
        // A full or unavailable store costs the offline copy, never the answer.
        debugPrint('Keeping an offline copy failed: $error');
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final offline = err.type == DioExceptionType.connectionError || err.type == DioExceptionType.connectionTimeout;
    if (offline && enabled() && OfflineCopies.keeps(err.requestOptions)) {
      final kept = await _copies().read(err.requestOptions);
      if (kept != null) {
        handler.resolve(
          Response(
            requestOptions: err.requestOptions,
            statusCode: 200,
            data: kept.data,
            headers: Headers.fromMap({
              header: [kept.savedAt.toIso8601String()],
            }),
          ),
        );
        return;
      }
    }
    handler.next(err);
  }
}
