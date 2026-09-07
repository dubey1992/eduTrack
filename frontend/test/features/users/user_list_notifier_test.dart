import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/users/application/user_list_notifier.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_user_repository.dart';

const _teacher = AppUser(
  id: 1,
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
);

void main() {
  ProviderContainer makeContainer(FakeUserRepository fake) {
    return ProviderContainer(overrides: [userRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the initial user list', () async {
    final container = makeContainer(FakeUserRepository(users: [_teacher]));
    addTearDown(container.dispose);

    final result = await container.read(userListNotifierProvider.future);

    expect(result, hasLength(1));
    expect(result.first.email, 'priya@example.com');
  });

  test('createUser() adds the new user to the list', () async {
    final container = makeContainer(FakeUserRepository());
    addTearDown(container.dispose);
    await container.read(userListNotifierProvider.future);

    await container
        .read(userListNotifierProvider.notifier)
        .createUser(
          firstName: 'Rahul',
          lastName: 'Verma',
          email: 'rahul@example.com',
          password: 'password123',
          role: UserRole.teacher,
        );

    final state = container.read(userListNotifierProvider).value;
    expect(state, hasLength(1));
    expect(state!.first.email, 'rahul@example.com');
  });

  test('setActive() updates that user in place without reloading everyone', () async {
    final container = makeContainer(FakeUserRepository(users: [_teacher]));
    addTearDown(container.dispose);
    await container.read(userListNotifierProvider.future);

    await container.read(userListNotifierProvider.notifier).setActive(_teacher, false);

    final state = container.read(userListNotifierProvider).value;
    expect(state!.first.status, UserStatus.inactive);
  });
}
