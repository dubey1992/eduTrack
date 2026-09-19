import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A small on-device store of strings by key - what the bus attendant's
/// phone keeps between app starts: the registered device, the trip marks
/// waiting to be sent, and the last copy of the trip to show with no signal.
///
/// Behind an interface so tests use an in-memory copy instead of the
/// platform's secure storage, which does not exist under `flutter test`.
abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The real store: Android's Keystore-backed storage, or the browser's
/// encrypted local storage on the web. The same place the session token
/// lives (see AuthTokenStorage) - a device secret is a credential, and a
/// trip's rider list names children, so neither belongs in plain storage.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final keyValueStoreProvider = Provider<KeyValueStore>((ref) => SecureKeyValueStore());
