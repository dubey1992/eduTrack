import 'package:edutrack_app/core/network/auth_token_storage.dart';

/// In-memory test double for [AuthTokenStorage] - avoids touching the real
/// FlutterSecureStorage platform channel, which isn't available in widget
/// tests.
class FakeAuthTokenStorage implements AuthTokenStorage {
  String? _token;
  String? _rememberedEmail;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clearToken() async => _token = null;

  @override
  Future<String?> readRememberedEmail() async => _rememberedEmail;

  @override
  Future<void> saveRememberedEmail(String email) async => _rememberedEmail = email;

  @override
  Future<void> clearRememberedEmail() async => _rememberedEmail = null;
}
