import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

/// This phone's registration for the Family app: the mobile number and the
/// long random secret the server handed back when it was registered.
/// Mobile + passcode only signs in together with the secret.
class FamilyDevice {
  const FamilyDevice({required this.mobile, required this.secret});

  final String mobile;
  final String secret;
}

final familyDeviceStorageProvider = Provider<FamilyDeviceStorage>(
  (ref) => FamilyDeviceStorage(ref.watch(keyValueStoreProvider)),
);

/// Keeps the [FamilyDevice] and the last-seen account in the secure store.
/// The secret is a credential: never logged, shown, or sent anywhere but
/// sign-in. Built like the bus attendant's (AttendantDeviceStorage), with
/// keys of its own.
class FamilyDeviceStorage {
  FamilyDeviceStorage(this._store);

  static const _mobileKey = 'family_mobile';
  static const _secretKey = 'family_device_secret';
  static const _sessionKey = 'family_session';

  final KeyValueStore _store;

  Future<FamilyDevice?> read() async {
    final mobile = await _store.read(_mobileKey);
    final secret = await _store.read(_secretKey);
    if (mobile == null || secret == null || secret.isEmpty) return null;

    return FamilyDevice(mobile: mobile, secret: secret);
  }

  /// The number last used here, kept after the secret is forgotten so the
  /// form can start from it.
  Future<String?> readMobile() => _store.read(_mobileKey);

  Future<void> save(FamilyDevice device) async {
    await _store.write(_mobileKey, device.mobile);
    await _store.write(_secretKey, device.secret);
  }

  /// Drops the secret after the server said this phone is not registered
  /// (removed by the office, or registered to another number).
  Future<void> forgetSecret() => _store.delete(_secretKey);

  /// The account as the server last described it, for opening the app with
  /// no signal. Null when there is none, or it cannot be read.
  Future<Map<String, dynamic>?> readSession() async {
    final raw = await _store.read(_sessionKey);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException catch (e) {
      debugPrint('Discarding an unreadable saved family session: ${e.message}');
      return null;
    }
  }

  Future<void> saveSession(Map<String, dynamic> json) => _store.write(_sessionKey, jsonEncode(json));

  Future<void> clearSession() => _store.delete(_sessionKey);
}
