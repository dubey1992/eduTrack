import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';
import 'models/saved_register.dart';

final registerStoreProvider = Provider<RegisterStore>((ref) => RegisterStore(ref.watch(keyValueStoreProvider)));

/// What the phone keeps for the register (docs/teacher-app.md, T2): the
/// registers waiting to be sent, the ones the server turned down, and each
/// class's list of students as last seen.
///
/// Anything unreadable is treated as empty rather than as an error - a
/// corrupt entry must not stop the app opening - and is logged.
class RegisterStore {
  RegisterStore(this._store);

  final KeyValueStore _store;

  static const _waitingKey = 'register.waiting';
  static const _unsentKey = 'register.unsent';
  static String _rosterKey(int sectionId) => 'register.roster.$sectionId';

  /// Which sections have a class list saved, so they can all be found again
  /// to be cleared: the phone's store cannot list its own keys.
  static const _rostersKey = 'register.rosters';

  Future<List<SavedRegister>> readWaiting() async => _readList(_waitingKey, (json) => SavedRegister.fromJson(json));

  Future<void> saveWaiting(List<SavedRegister> registers) =>
      _store.write(_waitingKey, jsonEncode([for (final r in registers) r.toJson()]));

  Future<List<UnsentRegister>> readUnsent() async => _readList(_unsentKey, (json) => UnsentRegister.fromJson(json));

  Future<void> saveUnsent(List<UnsentRegister> registers) =>
      _store.write(_unsentKey, jsonEncode([for (final r in registers) r.toJson()]));

  Future<List<CachedStudent>?> readRoster(int sectionId) async {
    final raw = await _store.read(_rosterKey(sectionId));
    if (raw == null) return null;

    try {
      return [for (final item in jsonDecode(raw) as List) CachedStudent.fromJson(item as Map<String, dynamic>)];
    } catch (error) {
      debugPrint('The saved class list for section $sectionId could not be read: $error');
      return null;
    }
  }

  Future<void> saveRoster(int sectionId, List<CachedStudent> students) async {
    await _store.write(_rosterKey(sectionId), jsonEncode([for (final s in students) s.toJson()]));

    final saved = await _savedRosterIds();
    if (!saved.contains(sectionId)) await _store.write(_rostersKey, jsonEncode([...saved, sectionId]));
  }

  /// Every saved class list, gone - on signing out (docs/security.md, "The
  /// phone apps"). They name children, and they are no business of whoever
  /// signs in next; a teacher's next sign-in downloads their own again.
  /// Registers waiting to be sent are not touched: they are that teacher's
  /// attendance, sent only under their own sign-in, and losing them would
  /// lose the day's register.
  Future<void> clearRosters() async {
    for (final sectionId in await _savedRosterIds()) {
      await _store.delete(_rosterKey(sectionId));
    }
    await _store.delete(_rostersKey);
  }

  Future<List<int>> _savedRosterIds() async {
    final raw = await _store.read(_rostersKey);
    if (raw == null) return [];

    try {
      return [for (final id in jsonDecode(raw) as List) id as int];
    } catch (error) {
      debugPrint('The list of saved class lists could not be read: $error');
      return [];
    }
  }

  Future<List<T>> _readList<T>(String key, T Function(Map<String, dynamic>) parse) async {
    final raw = await _store.read(key);
    if (raw == null) return [];

    try {
      return [for (final item in jsonDecode(raw) as List) parse(item as Map<String, dynamic>)];
    } catch (error) {
      debugPrint('Saved registers under $key could not be read: $error');
      return [];
    }
  }
}
