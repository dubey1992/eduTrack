import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Sanctum API bearer token on-device, outside plain
/// SharedPreferences, since it is a credential (see backend CLAUDE.md rule
/// 11: never log tokens; this extends that care to client-side storage).
///
/// Also holds the "Remember me" email - not a credential, but kept here too
/// rather than adding a second storage dependency just for one string.
class AuthTokenStorage {
  AuthTokenStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _rememberedEmailKey = 'remembered_email';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readRememberedEmail() => _storage.read(key: _rememberedEmailKey);

  Future<void> saveRememberedEmail(String email) => _storage.write(key: _rememberedEmailKey, value: email);

  Future<void> clearRememberedEmail() => _storage.delete(key: _rememberedEmailKey);
}
