import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/session_ended_notifier.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/my_register/data/register_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/in_memory_key_value_store.dart';

/// A session the server has ended - signed out elsewhere, expired, the
/// account switched off, a bus phone revoked - signs out on this device too
/// (docs/security.md, "The phone apps").
void main() {
  group('which answers end the session', () {
    test('a 401 to a request that carried the session', () {
      expect(endsSession(status: 401, path: '/students', carriedSession: true), isTrue);
    });

    test('not a wrong password or passcode at sign-in', () {
      expect(endsSession(status: 401, path: '/auth/login', carriedSession: true), isFalse);
      expect(endsSession(status: 401, path: '/auth/attendant/login', carriedSession: false), isFalse);
    });

    test('not a request that had no session to end', () {
      expect(endsSession(status: 401, path: '/students', carriedSession: false), isFalse);
    });

    test('not any other refusal', () {
      expect(endsSession(status: 403, path: '/students', carriedSession: true), isFalse);
      expect(endsSession(status: 503, path: '/students', carriedSession: true), isFalse);
    });
  });

  group('when it ends', () {
    const teacher = AuthenticatedUser(id: 7, name: 'Priya', email: 'priya@example.com', role: UserRole.teacher);

    late FakeAuthRepository auth;
    late InMemoryKeyValueStore store;
    late ProviderContainer container;

    setUp(() async {
      auth = FakeAuthRepository(sessionOnRestore: teacher);
      store = InMemoryKeyValueStore();
      container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(auth), keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(authNotifierProvider.future);
    });

    test('this device signs out without asking the server, and keeps what is still to send', () async {
      await container.read(registerStoreProvider).saveRoster(11, const []);
      store.values['register.waiting'] = '[]';

      container.read(sessionEndedProvider.notifier).report();
      await pumpEventQueue();

      expect(container.read(authNotifierProvider).value, isNull);
      expect(auth.forgotSession, isTrue);
      expect(auth.loggedOutCalled, isFalse, reason: 'the server already said the session is over');
      expect(store.values.keys, ['register.waiting'], reason: 'class lists go; unsent registers stay');
    });

    test('signing in again clears the message', () async {
      container.read(sessionEndedProvider.notifier).report();
      await pumpEventQueue();

      await container.read(authNotifierProvider.notifier).login(email: 'priya@example.com', password: 'x');

      expect(container.read(sessionEndedProvider), isFalse);
    });
  });
}
