import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/staff/application/staff_list_notifier.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_staff_repository.dart';
import '../../support/fake_user_repository.dart';

StaffProfile _profile({int id = 1, int userId = 1, UserStatus status = UserStatus.active}) {
  return StaffProfile(
    id: id,
    userId: userId,
    employeeId: 'TCH-00$id',
    firstName: 'Priya',
    lastName: 'Sharma',
    name: 'Priya Sharma',
    email: 'priya@example.com',
    mobile: null,
    role: UserRole.teacher,
    status: status,
    schoolId: 1,
    schoolName: 'Sunrise Public School',
    departmentId: null,
    departmentName: null,
    designation: null,
    joiningDate: DateTime(2024, 6, 1),
    address: null,
    classTeacherOf: const [],
  );
}

void main() {
  ProviderContainer makeContainer({FakeStaffRepository? staffFake, FakeUserRepository? userFake}) {
    return ProviderContainer(
      overrides: [
        staffRepositoryProvider.overrideWithValue(staffFake ?? FakeStaffRepository()),
        userRepositoryProvider.overrideWithValue(userFake ?? FakeUserRepository()),
      ],
    );
  }

  test('build() loads the initial staff list', () async {
    final container = makeContainer(staffFake: FakeStaffRepository(staff: [_profile()]));
    addTearDown(container.dispose);

    final result = await container.read(staffListNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.employeeId, 'TCH-001');
  });

  test('createEmployee() adds the new employee to the list', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(staffListNotifierProvider.future);

    await container
        .read(staffListNotifierProvider.notifier)
        .createEmployee(
          firstName: 'Rahul',
          lastName: 'Verma',
          email: 'rahul@example.com',
          password: 'password123',
          role: UserRole.teacher,
          employeeId: 'TCH-018',
          joiningDate: DateTime(2025, 1, 1),
        );

    final state = container.read(staffListNotifierProvider).value;
    expect(state!.items, hasLength(1));
    expect(state.items.first.employeeId, 'TCH-018');
  });

  test('setActive() updates that employees status via the Users endpoint', () async {
    final profile = _profile(status: UserStatus.active);
    final matchingUser = AppUser(
      id: profile.userId,
      firstName: 'Priya',
      lastName: 'Sharma',
      name: 'Priya Sharma',
      email: 'priya@example.com',
      mobile: null,
      role: UserRole.teacher,
      status: UserStatus.active,
    );
    final container = makeContainer(
      staffFake: FakeStaffRepository(staff: [profile]),
      userFake: FakeUserRepository(users: [matchingUser]),
    );
    addTearDown(container.dispose);
    await container.read(staffListNotifierProvider.future);

    await container.read(staffListNotifierProvider.notifier).setActive(profile, false);

    final state = container.read(staffListNotifierProvider).value;
    expect(state!.items.first.status, UserStatus.inactive);
  });

  test('setSearch() filters server-side and resets to page 1', () async {
    final priya = _profile(id: 1);
    final rahul = StaffProfile(
      id: 2,
      userId: 2,
      employeeId: 'TCH-002',
      firstName: 'Rahul',
      lastName: 'Verma',
      name: 'Rahul Verma',
      email: 'rahul@example.com',
      mobile: null,
      role: UserRole.teacher,
      status: UserStatus.active,
      schoolId: 1,
      schoolName: 'Sunrise Public School',
      departmentId: null,
      departmentName: null,
      designation: null,
      joiningDate: DateTime(2024, 6, 1),
      address: null,
      classTeacherOf: const [],
    );
    final container = makeContainer(staffFake: FakeStaffRepository(staff: [priya, rahul]));
    addTearDown(container.dispose);
    await container.read(staffListNotifierProvider.future);

    await container.read(staffListNotifierProvider.notifier).setSearch('Priya');

    final state = container.read(staffListNotifierProvider).value!;
    expect(state.items, hasLength(1));
    expect(state.items.first.name, 'Priya Sharma');
    expect(state.currentPage, 1);
  });
}
