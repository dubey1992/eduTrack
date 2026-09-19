import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/auth/data/attendant_device_storage.dart';
import 'package:edutrack_app/features/auth/data/auth_api.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendant_auth_api.dart';
import '../../support/fake_auth_token_storage.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/my_trip_fixtures.dart';

/// /me answered from memory - or not at all.
class _FakeAuthApi implements AuthApi {
  _FakeAuthApi(this.answer);

  /// The payload, or the failure to throw.
  Object answer;

  @override
  Future<Map<String, dynamic>> meJson() async {
    final answer = this.answer;
    if (answer is DioException) throw answer;
    return answer as Map<String, dynamic>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A bus loses signal; an attendant opening the app there must still reach
/// the trip kept on the phone (docs/maps.md, "Offline").
void main() {
  late InMemoryKeyValueStore store;
  late FakeAuthTokenStorage tokens;

  setUp(() async {
    store = InMemoryKeyValueStore();
    tokens = FakeAuthTokenStorage();
    await tokens.saveToken('attendant-token');
  });

  AuthRepository repository(Object answer) =>
      AuthRepository(_FakeAuthApi(answer), tokens, AttendantDeviceStorage(store));

  test('with signal, an attendant session is kept on the phone', () async {
    final user = await repository(attendantUserJson()).restoreSession();

    expect(user?.role, UserRole.busAttendant);
    expect(jsonDecode(store.values['attendant_session']!)['name'], 'Asha Attendant');
  });

  test('with no signal, the kept session opens the app and the token stays', () async {
    await repository(attendantUserJson()).restoreSession();

    final user = await repository(offlineError('/me')).restoreSession();

    expect(user?.name, 'Asha Attendant');
    expect(await tokens.readToken(), 'attendant-token');
  });

  test('with no signal and nothing kept, nobody is signed in', () async {
    final user = await repository(offlineError('/me')).restoreSession();

    expect(user, isNull);
    expect(await tokens.readToken(), isNull);
  });

  test('a session the server refuses is not revived from the phone', () async {
    await repository(attendantUserJson()).restoreSession();

    final user = await repository(apiError('/me', 401, 'UNAUTHENTICATED', 'Unauthenticated.')).restoreSession();

    expect(user, isNull);
    expect(await tokens.readToken(), isNull);
  });

  test("other roles' sessions are not kept on the phone", () async {
    final admin = {...attendantUserJson(), 'role': 'SCHOOL_ADMIN'};
    await repository(admin).restoreSession();

    expect(store.values['attendant_session'], isNull);
  });
}
