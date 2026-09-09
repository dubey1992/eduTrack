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

List<AppUser> _users(int count) {
  return [
    for (var i = 1; i <= count; i++)
      AppUser(
        id: i,
        firstName: 'User',
        lastName: '$i',
        name: 'User $i',
        email: 'user$i@example.com',
        mobile: null,
        role: UserRole.teacher,
        status: UserStatus.active,
      ),
  ];
}

void main() {
  ProviderContainer makeContainer(FakeUserRepository fake) {
    return ProviderContainer(overrides: [userRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the initial page of users', () async {
    final container = makeContainer(FakeUserRepository(users: [_teacher]));
    addTearDown(container.dispose);

    final result = await container.read(userListNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.email, 'priya@example.com');
    expect(result.currentPage, 1);
    expect(result.total, 1);
    expect(result.perPage, 20);
  });

  test('createUser() adds the new user and returns to page 1', () async {
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
    expect(state!.items, hasLength(1));
    expect(state.items.first.email, 'rahul@example.com');
  });

  test('updateUser() saves the changes in place', () async {
    final container = makeContainer(FakeUserRepository(users: [_teacher]));
    addTearDown(container.dispose);
    await container.read(userListNotifierProvider.future);

    await container
        .read(userListNotifierProvider.notifier)
        .updateUser(_teacher, firstName: 'Priyanka', email: 'priyanka@example.com');

    final state = container.read(userListNotifierProvider).value;
    expect(state!.items.first.firstName, 'Priyanka');
    expect(state.items.first.name, 'Priyanka Sharma');
    expect(state.items.first.email, 'priyanka@example.com');
  });

  test('setSchoolFilter() refetches scoped to that school', () async {
    final fake = FakeUserRepository(users: [_teacher]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(userListNotifierProvider.future);
    expect(fake.lastListSchoolId, isNull);

    await container.read(userListNotifierProvider.notifier).setSchoolFilter(7);

    expect(fake.lastListSchoolId, 7);
  });

  test('setActive() updates that user in place without reloading everyone', () async {
    final container = makeContainer(FakeUserRepository(users: [_teacher]));
    addTearDown(container.dispose);
    await container.read(userListNotifierProvider.future);

    await container.read(userListNotifierProvider.notifier).setActive(_teacher, false);

    final state = container.read(userListNotifierProvider).value;
    expect(state!.items.first.status, UserStatus.inactive);
  });

  test('goToPage() fetches the requested page', () async {
    final container = makeContainer(FakeUserRepository(users: _users(45)));
    addTearDown(container.dispose);
    await container.read(userListNotifierProvider.future);

    await container.read(userListNotifierProvider.notifier).goToPage(2);

    final state = container.read(userListNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(20));
    expect(state.items.first.id, 21);
  });

  test('setPerPage() changes the page size and resets to page 1', () async {
    final container = makeContainer(FakeUserRepository(users: _users(45)));
    addTearDown(container.dispose);
    await container.read(userListNotifierProvider.future);
    await container.read(userListNotifierProvider.notifier).goToPage(2);

    await container.read(userListNotifierProvider.notifier).setPerPage(50);

    final state = container.read(userListNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.perPage, 50);
    expect(state.items, hasLength(45));
  });

  test('lastPage reflects the total across all pages', () async {
    final container = makeContainer(FakeUserRepository(users: _users(45)));
    addTearDown(container.dispose);

    final result = await container.read(userListNotifierProvider.future);

    expect(result.total, 45);
    expect(result.lastPage, 3);
  });
}
