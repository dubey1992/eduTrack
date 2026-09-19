import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/staff/application/attendant_access_notifier.dart';
import 'package:edutrack_app/features/staff/data/attendant_access_repository.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attendant_fixtures.dart';
import '../../support/fake_attendant_access_repository.dart';
import '../../support/fake_user_repository.dart';

const _attendantUser = AppUser(
  id: 131,
  firstName: 'Meera',
  lastName: 'Sharma',
  name: 'Meera Sharma',
  email: 'attendant@no-email.invalid',
  mobile: '+91 9876543210',
  role: UserRole.busAttendant,
  status: UserStatus.active,
);

ProviderContainer _container(FakeAttendantAccessRepository access, FakeUserRepository users) {
  final container = ProviderContainer(
    overrides: [
      attendantAccessRepositoryProvider.overrideWithValue(access),
      userRepositoryProvider.overrideWithValue(users),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('loads the attendant\'s sign-in for their staff profile', () async {
    final container = _container(FakeAttendantAccessRepository(access: setUpAccess), FakeUserRepository());
    container.listen(attendantAccessProvider(31), (_, _) {});

    final access = await container.read(attendantAccessProvider(31).future);

    expect(access.loginMobile, '+919876543210');
    expect(access.devices, hasLength(2));
  });

  test('issuing a code returns it and re-reads the panel so the code shows as pending', () async {
    final fake = FakeAttendantAccessRepository(access: freshAccess);
    final container = _container(fake, FakeUserRepository());
    container.listen(attendantAccessProvider(31), (_, _) {});
    await container.read(attendantAccessProvider(31).future);

    final code = await container.read(attendantAccessProvider(31).notifier).issueSetupCode();

    expect(code.setupCode, '12345678');
    expect(code.loginMobile, '+919876543210');
    expect(container.read(attendantAccessProvider(31)).value!.setupCodePending, isTrue);
  });

  test('a refused code is thrown to the caller and leaves the panel as it was', () async {
    final fake = FakeAttendantAccessRepository(
      access: freshAccess,
      failIssueWith: const Failure(code: 'ACCOUNT_INACTIVE', message: 'This account is switched off.'),
    );
    final container = _container(fake, FakeUserRepository());
    container.listen(attendantAccessProvider(31), (_, _) {});
    await container.read(attendantAccessProvider(31).future);

    await expectLater(
      container.read(attendantAccessProvider(31).notifier).issueSetupCode(),
      throwsA(isA<Failure>().having((f) => f.message, 'message', 'This account is switched off.')),
    );
    expect(container.read(attendantAccessProvider(31)).value!.setupCodePending, isFalse);
  });

  test('removing a phone takes the answer as the new state', () async {
    final fake = FakeAttendantAccessRepository(access: setUpAccess);
    final container = _container(fake, FakeUserRepository());
    container.listen(attendantAccessProvider(31), (_, _) {});
    await container.read(attendantAccessProvider(31).future);

    await container.read(attendantAccessProvider(31).notifier).removeDevice(redmiPhone);

    expect(fake.lastRemovedDeviceId, 7);
    expect(container.read(attendantAccessProvider(31)).value!.devices.every((d) => !d.isActive), isTrue);
  });

  test('unlock goes through the ordinary user unlock with the user id, then re-reads', () async {
    final fake = FakeAttendantAccessRepository(access: setUpAccess.copyWith(isLocked: true));
    final users = FakeUserRepository(users: [_attendantUser]);
    final container = _container(fake, users);
    container.listen(attendantAccessProvider(31), (_, _) {});
    await container.read(attendantAccessProvider(31).future);
    final getsBefore = fake.getCalls;

    fake.unlockOnServer();
    await container.read(attendantAccessProvider(31).notifier).unlock(131);

    expect(users.unlockCalls, 1);
    expect(fake.getCalls, getsBefore + 1);
    expect(container.read(attendantAccessProvider(31)).value!.isLocked, isFalse);
  });
}
