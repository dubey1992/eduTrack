import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';
import 'models/location_point.dart';
import 'models/not_sent_mark.dart';
import 'models/trip_mark.dart';

final tripOfflineStoreProvider = Provider<TripOfflineStore>(
  (ref) => TripOfflineStore(ref.watch(keyValueStoreProvider)),
);

/// What the attendant's phone keeps so a trip survives no signal and an app
/// restart (docs/maps.md, "Offline"): the marks waiting to be sent, the ones
/// the server turned down, buffered GPS points, and the last copy of the
/// routes and trips to show when the API cannot be reached.
///
/// Everything is small JSON in the secure store - a bus has a few dozen
/// children, not thousands - so each list is read and written whole.
class TripOfflineStore {
  TripOfflineStore(this._store);

  static const _marksKey = 'my_trip.marks';
  static const _notSentKey = 'my_trip.not_sent';
  static const _pointsKey = 'my_trip.points';
  static const _routesKey = 'my_trip.routes';
  static const _tripIdsKey = 'my_trip.trip_ids';
  static const _shareLocationKey = 'my_trip.share_location';

  static String _tripKey(int tripId) => 'my_trip.trip.$tripId';

  final KeyValueStore _store;

  Future<List<TripMark>> readMarks() async => (await _readList(_marksKey)).map(TripMark.fromJson).toList();

  Future<void> saveMarks(List<TripMark> marks) => _writeList(_marksKey, marks.map((m) => m.toJson()));

  Future<List<NotSentMark>> readNotSent() async => (await _readList(_notSentKey)).map(NotSentMark.fromJson).toList();

  Future<void> saveNotSent(List<NotSentMark> marks) => _writeList(_notSentKey, marks.map((m) => m.toJson()));

  Future<List<LocationPoint>> readPoints() async => (await _readList(_pointsKey)).map(LocationPoint.fromJson).toList();

  Future<void> savePoints(List<LocationPoint> points) => _writeList(_pointsKey, points.map((p) => p.toJson()));

  Future<Map<String, dynamic>?> readRoutes() => _readMap(_routesKey);

  Future<void> saveRoutes(Map<String, dynamic> json) => _store.write(_routesKey, jsonEncode(json));

  Future<Map<String, dynamic>?> readTrip(int tripId) => _readMap(_tripKey(tripId));

  Future<void> saveTrip(int tripId, Map<String, dynamic> json) async {
    await _store.write(_tripKey(tripId), jsonEncode(json));

    final ids = await _readTripIds();
    if (!ids.contains(tripId)) await _store.write(_tripIdsKey, jsonEncode([...ids, tripId]));
  }

  /// The attendant's own choice on "Share my location"; null until they make one.
  Future<bool?> readShareLocation() async {
    final value = await _store.read(_shareLocationKey);
    return value == null ? null : value == 'true';
  }

  Future<void> saveShareLocation(bool share) => _store.write(_shareLocationKey, share.toString());

  /// Forgets everything - on sign-out, so the next person on this phone sees
  /// none of it.
  Future<void> clear() async {
    for (final tripId in await _readTripIds()) {
      await _store.delete(_tripKey(tripId));
    }
    for (final key in [_marksKey, _notSentKey, _pointsKey, _routesKey, _tripIdsKey, _shareLocationKey]) {
      await _store.delete(key);
    }
  }

  Future<List<int>> _readTripIds() async {
    final raw = await _decode(_tripIdsKey);
    return raw is List ? raw.whereType<int>().toList() : const [];
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final raw = await _decode(key);
    return raw is List ? raw.whereType<Map<String, dynamic>>().toList() : const [];
  }

  Future<Map<String, dynamic>?> _readMap(String key) async {
    final raw = await _decode(key);
    return raw is Map<String, dynamic> ? raw : null;
  }

  Future<void> _writeList(String key, Iterable<Map<String, dynamic>> items) {
    return _store.write(key, jsonEncode(items.toList()));
  }

  /// The stored JSON, or null. A copy that no longer parses (an older app
  /// version, a half-written value) is reported and treated as empty rather
  /// than stopping the trip screen from opening.
  Future<Object?> _decode(String key) async {
    final raw = await _store.read(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      return jsonDecode(raw);
    } on FormatException catch (e) {
      debugPrint('Discarding unreadable offline data under $key: ${e.message}');
      return null;
    }
  }
}
