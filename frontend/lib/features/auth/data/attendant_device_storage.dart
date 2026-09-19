import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

/// The phone's registration as a bus attendant's device: the mobile number
/// it was registered for and the long random secret the server handed back.
/// Mobile + passcode only signs in together with this secret (docs/maps.md,
/// "The Bus Attendant").
class AttendantDevice {
  const AttendantDevice({required this.mobile, required this.secret});

  final String mobile;
  final String secret;
}

final attendantDeviceStorageProvider = Provider<AttendantDeviceStorage>(
  (ref) => AttendantDeviceStorage(ref.watch(keyValueStoreProvider)),
);

/// Keeps the [AttendantDevice] in the secure store. The secret is a
/// credential: it is never logged, shown or sent anywhere but sign-in.
class AttendantDeviceStorage {
  AttendantDeviceStorage(this._store);

  static const _mobileKey = 'attendant_mobile';
  static const _secretKey = 'attendant_device_secret';
  static const _sessionKey = 'attendant_session';

  final KeyValueStore _store;

  /// The registration, or null when this phone has none yet.
  Future<AttendantDevice?> read() async {
    final mobile = await _store.read(_mobileKey);
    final secret = await _store.read(_secretKey);
    if (mobile == null || secret == null || secret.isEmpty) return null;

    return AttendantDevice(mobile: mobile, secret: secret);
  }

  /// The number last used here, kept even after the secret is forgotten so
  /// the register form can start from it.
  Future<String?> readMobile() => _store.read(_mobileKey);

  Future<void> save(AttendantDevice device) async {
    await _store.write(_mobileKey, device.mobile);
    await _store.write(_secretKey, device.secret);
  }

  /// Drops the secret after the server said this phone is not registered
  /// (revoked by the office, or registered to another number).
  Future<void> forgetSecret() => _store.delete(_secretKey);

  /// The signed-in attendant as the server last described them (the /me
  /// payload), for opening the app with no signal. Null when there is none.
  Future<Map<String, dynamic>?> readSession() async {
    final raw = await _store.read(_sessionKey);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException catch (e) {
      debugPrint('Discarding an unreadable saved attendant session: ${e.message}');
      return null;
    }
  }

  Future<void> saveSession(Map<String, dynamic> json) => _store.write(_sessionKey, jsonEncode(json));

  Future<void> clearSession() => _store.delete(_sessionKey);
}
