import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

final familySavedCopiesProvider = Provider<FamilySavedCopies>(
  (ref) => FamilySavedCopies(ref.watch(keyValueStoreProvider)),
);

/// The last answer each Family screen got, kept on the phone
/// (docs/mobile-apps-review.md, 2.2): opened with no signal, a screen shows
/// what was true when the phone last had one, and says when - as Home
/// already did. Kept as the server's own JSON, so nothing about a screen's
/// data has to be written back out.
///
/// Every name is listed under one key, so signing out forgets them all:
/// they are a child's records, and a phone may pass to somebody else.
class FamilySavedCopies {
  FamilySavedCopies(this._store);

  static const _indexKey = 'family_copies';

  final KeyValueStore _store;

  static String _key(String name) => 'family_copy.$name';

  Future<void> save(String name, Object json, DateTime at) async {
    await _remember(_key(name));
    await _store.write(_key(name), jsonEncode({'at': at.toIso8601String(), 'data': json}));
  }

  Future<({Object json, DateTime at})?> read(String name) async {
    final raw = await _store.read(_key(name));
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (json: decoded['data'] as Object, at: DateTime.parse(decoded['at'] as String));
    } on Object catch (error) {
      debugPrint('Discarding an unreadable saved copy of $name: $error');
      return null;
    }
  }

  /// Another store key to forget on sign-out - Home's own copy.
  Future<void> remember(String storeKey) => _remember(storeKey);

  Future<void> _remember(String storeKey) async {
    final keys = await _keys();
    if (keys.contains(storeKey)) return;
    await _store.write(_indexKey, jsonEncode([...keys, storeKey]));
  }

  Future<List<String>> _keys() async {
    final raw = await _store.read(_indexKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } on Object catch (error) {
      debugPrint('Unreadable list of saved copies: $error');
      return const [];
    }
  }

  /// On sign-out.
  Future<void> clear() async {
    for (final key in await _keys()) {
      await _store.delete(key);
    }
    await _store.delete(_indexKey);
  }
}

/// No answer at all - what a saved copy stands in for. A refusal is the
/// server's answer and is never covered up by an old copy.
bool isNoSignal(DioException error) =>
    error.response == null &&
    (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.unknown);
