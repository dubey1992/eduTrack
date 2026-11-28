import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/storage/key_value_store.dart';
import 'offline_snapshot.dart';

/// Where the offline copy lives on the computer (docs/offline-web.md, O2):
/// in the app's encrypted browser storage, under the person who said the
/// computer is one they trust. Wiped at sign-out.
class OfflineRecordsStore {
  OfflineRecordsStore(this._store);

  final KeyValueStore _store;

  static const _trustedKey = 'offline.trusted_user';
  static const _snapshotKey = 'offline.snapshot';

  /// Whether [userId] ticked "This is a school computer I trust" here.
  Future<bool> isTrustedBy(int userId) async => await _store.read(_trustedKey) == '$userId';

  Future<void> trust(int userId) => _store.write(_trustedKey, '$userId');

  Future<void> distrust() => _store.delete(_trustedKey);

  Future<OfflineSnapshot?> read() async {
    final raw = await _store.read(_snapshotKey);
    if (raw == null) return null;
    try {
      return OfflineSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      // An unreadable copy is no copy: dropped, never a broken screen.
      debugPrint('Unreadable offline copy dropped: $error');
      await _store.delete(_snapshotKey);
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> json) => _store.write(_snapshotKey, jsonEncode(json));

  /// The copy and the trust, both - at sign-out.
  Future<void> clear() async {
    await _store.delete(_snapshotKey);
    await _store.delete(_trustedKey);
  }
}

final offlineRecordsStoreProvider = Provider<OfflineRecordsStore>(
  (ref) => OfflineRecordsStore(ref.watch(keyValueStoreProvider)),
);

/// `GET offline/snapshot`, kept as the raw JSON it arrives as.
class OfflineSnapshotApi {
  OfflineSnapshotApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> fetch() async {
    try {
      final response = await _dio.get('/offline/snapshot');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}

final offlineSnapshotApiProvider = Provider<OfflineSnapshotApi>(
  (ref) => OfflineSnapshotApi(ref.watch(dioClientProvider)),
);
