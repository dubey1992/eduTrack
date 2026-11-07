import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

final familyTodayCacheProvider = Provider<FamilyTodayCache>(
  (ref) => FamilyTodayCache(ref.watch(keyValueStoreProvider)),
);

/// Each child's last Home, kept on the phone: opened with no signal, the
/// app shows what was true when it last had one, and says when that was -
/// as the driver app keeps the trip (docs/parent-student-app.md, "five states").
class FamilyTodayCache {
  FamilyTodayCache(this._store);

  final KeyValueStore _store;

  static String _key(int childId) => 'family_today_$childId';

  Future<void> save(int childId, Map<String, dynamic> json, DateTime at) =>
      _store.write(_key(childId), jsonEncode({'at': at.toIso8601String(), 'data': json}));

  /// The last copy and when it was fetched, or null when there is none.
  Future<({Map<String, dynamic> json, DateTime at})?> read(int childId) async {
    final raw = await _store.read(_key(childId));
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (json: decoded['data'] as Map<String, dynamic>, at: DateTime.parse(decoded['at'] as String));
    } on Object catch (error) {
      debugPrint('Discarding an unreadable saved Home for child $childId: $error');
      return null;
    }
  }
}
