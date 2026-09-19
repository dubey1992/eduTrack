import 'package:edutrack_app/core/storage/key_value_store.dart';

/// [KeyValueStore] kept in a map - the platform's secure storage does not
/// exist under `flutter test`. Share one instance between two containers to
/// stand for the same phone across an app restart.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
