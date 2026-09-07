import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  ProviderContainer makeContainer(FakeAuthRepository fake) {
    return ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() restores no session when nothing is stored', () async {
    final container = makeContainer(FakeAuthRepository());
    addTearDown(container.dispose);

    final result = await container.read(authNotifierProvider.future);

    expect(result, isNull);
  });

  test('build() restores the existing session when a valid token is stored', () async {
    const user = AuthenticatedUser(
      id: 7,
      name: 'Priya Sharma',
      email: 'priya@example.com',
      role: UserRole.teacher,
    );
    final container = makeContainer(FakeAuthRepository(sessionOnRestore: user));
    addTearDown(container.dispose);

    final result = await container.read(authNotifierProvider.future);

    expect(result?.id, 7);
  });

  test('login() succeeds and stores the authenticated user', () async {
    final container = makeContainer(FakeAuthRepository());
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);

    await container
        .read(authNotifierProvider.notifier)
        .login(email: 'test@example.com', password: 'password');

    final state = container.read(authNotifierProvider);
    expect(state.hasValue, isTrue);
    expect(state.value?.email, 'test@example.com');
  });

  test('login() surfaces a Failure when credentials are rejected', () async {
    final fake = FakeAuthRepository(
      failLoginWith: const Failure(code: 'UNAUTHENTICATED', message: 'Invalid credentials'),
    );
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);

    await container.read(authNotifierProvider.notifier).login(email: 'test@example.com', password: 'wrong');

    final state = container.read(authNotifierProvider);
    expect(state.hasError, isTrue);
    expect((state.error as Failure).code, 'UNAUTHENTICATED');
  });

  test('logout() clears the session and calls the repository', () async {
    const user = AuthenticatedUser(
      id: 1,
      name: 'Test User',
      email: 'test@example.com',
      role: UserRole.superAdmin,
    );
    final fake = FakeAuthRepository(sessionOnRestore: user);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);

    await container.read(authNotifierProvider.notifier).logout();

    expect(fake.loggedOutCalled, isTrue);
    expect(container.read(authNotifierProvider).value, isNull);
  });
}
