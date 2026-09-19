import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/profile/application/profile_notifier.dart';
import 'package:edutrack_app/features/profile/data/profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_profile_repository.dart';

const _session = AuthenticatedUser(id: 12, name: 'Asha Rao', email: 'asha@example.com', role: UserRole.teacher);

/// A signed-in session and a loaded profile, the way the screen starts.
Future<ProviderContainer> loadedContainer(FakeProfileRepository fake, FakeAuthRepository auth) async {
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [profileRepositoryProvider.overrideWithValue(fake), authRepositoryProvider.overrideWithValue(auth)],
  );
  addTearDown(container.dispose);

  await container.read(authNotifierProvider.future);
  await container.read(profileNotifierProvider.future);
  return container;
}

const _validation = Failure(
  code: 'VALIDATION_ERROR',
  message: 'The first name field is required.',
  details: {
    'errors': {
      'first_name': ['The first name field is required.'],
    },
  },
);

/// The user's own profile: loaded once, replaced by whatever each change
/// hands back, followed by a fresh session read so the header catches up,
/// and left alone when a change fails.
void main() {
  late FakeProfileRepository fake;
  late FakeAuthRepository auth;

  setUp(() {
    fake = FakeProfileRepository();
    auth = FakeAuthRepository(sessionOnRestore: _session);
  });

  test('loads the profile from the API', () async {
    final container = await loadedContainer(fake, auth);

    final profile = container.read(profileNotifierProvider).value!;
    expect(profile.name, 'Asha Rao');
    expect(profile.hasStaffRecord, isTrue);
    expect(profile.employment!.employeeId, 'EMP-042');
    expect(fake.getCalls, 1);
  });

  test('a failed load is the error state; load() tries again', () async {
    fake.failGetWith = Failure.network();
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [profileRepositoryProvider.overrideWithValue(fake), authRepositoryProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);

    await expectLater(container.read(profileNotifierProvider.future), throwsA(isA<Failure>()));
    expect(container.read(profileNotifierProvider).hasError, isTrue);

    fake.failGetWith = null;
    await container.read(profileNotifierProvider.notifier).load();

    expect(fake.getCalls, 2);
    expect(container.read(profileNotifierProvider).value!.email, 'asha@example.com');
  });

  group('updateDetails', () {
    test('sends only the fields that changed', () async {
      final container = await loadedContainer(fake, auth);

      await container
          .read(profileNotifierProvider.notifier)
          .updateDetails(firstName: 'Asha', lastName: 'Rao-Iyer', mobile: '+91 9876543210', address: '12 Lake Road');

      expect(fake.lastUpdate, {'last_name': 'Rao-Iyer'});
      expect(container.read(profileNotifierProvider).value!.name, 'Asha Rao-Iyer');
    });

    test('an empty mobile or address is sent to clear it', () async {
      final container = await loadedContainer(fake, auth);

      await container.read(profileNotifierProvider.notifier).updateDetails(mobile: '', address: '');

      expect(fake.lastUpdate, {'mobile': '', 'address': ''});
      final profile = container.read(profileNotifierProvider).value!;
      expect(profile.mobile, isNull);
      expect(profile.address, isNull);
    });

    test('nothing changed sends nothing and does not refresh the session', () async {
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;

      await container
          .read(profileNotifierProvider.notifier)
          .updateDetails(firstName: 'Asha', lastName: 'Rao', mobile: '+91 9876543210');

      expect(fake.updateCalls, 0);
      expect(auth.restoreCalls, restoresBefore);
    });

    test('refreshes the session so the header shows the new name', () async {
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;
      auth.sessionOnRestore = const AuthenticatedUser(
        id: 12,
        name: 'Asha Rao-Iyer',
        email: 'asha@example.com',
        role: UserRole.teacher,
      );

      await container.read(profileNotifierProvider.notifier).updateDetails(lastName: 'Rao-Iyer');

      expect(auth.restoreCalls, restoresBefore + 1);
      expect(container.read(authNotifierProvider).value!.name, 'Asha Rao-Iyer');
    });

    test('a refused update throws with its field errors and keeps the profile', () async {
      fake.failUpdateWith = _validation;
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;

      await expectLater(
        container.read(profileNotifierProvider.notifier).updateDetails(firstName: ''),
        throwsA(isA<Failure>().having((f) => f.validationErrors['first_name'], 'first_name', isNotEmpty)),
      );

      final state = container.read(profileNotifierProvider);
      expect(state.hasError, isFalse);
      expect(state.value!.firstName, 'Asha');
      expect(auth.restoreCalls, restoresBefore);
    });
  });

  group('changeEmail', () {
    test('sends the address and password, then refreshes the session', () async {
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;

      await container
          .read(profileNotifierProvider.notifier)
          .changeEmail(email: 'asha.rao@example.com', currentPassword: 'secret-1');

      expect(fake.lastEmailChange, (email: 'asha.rao@example.com', currentPassword: 'secret-1'));
      expect(container.read(profileNotifierProvider).value!.email, 'asha.rao@example.com');
      expect(auth.restoreCalls, restoresBefore + 1);
    });

    test('a wrong password throws and keeps the old email', () async {
      fake.failEmailWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'That is not your current password.',
        details: {
          'errors': {
            'current_password': ['That is not your current password.'],
          },
        },
      );
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;

      await expectLater(
        container.read(profileNotifierProvider.notifier).changeEmail(email: 'new@example.com', currentPassword: 'x'),
        throwsA(isA<Failure>()),
      );

      expect(container.read(profileNotifierProvider).value!.email, 'asha@example.com');
      expect(auth.restoreCalls, restoresBefore);
    });
  });

  group('photo', () {
    test('upload sends the bytes and name, takes the new photo url and refreshes the session', () async {
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;

      await container.read(profileNotifierProvider.notifier).uploadPhoto(bytes: [1, 2, 3], fileName: 'me.png');

      expect(fake.lastUpload!.bytes, [1, 2, 3]);
      expect(fake.lastUpload!.fileName, 'me.png');
      expect(container.read(profileNotifierProvider).value!.photoUrl, '/users/12/photo?v=new');
      expect(auth.restoreCalls, restoresBefore + 1);
    });

    test('a refused upload throws with the server reason and keeps the profile', () async {
      fake.failUploadWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The photo must be a JPEG or PNG image.',
        details: {
          'errors': {
            'photo': ['The photo must be a JPEG or PNG image.'],
          },
        },
      );
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;

      await expectLater(
        container.read(profileNotifierProvider.notifier).uploadPhoto(bytes: [1], fileName: 'me.gif'),
        throwsA(isA<Failure>().having((f) => f.validationErrors['photo'], 'photo', isNotEmpty)),
      );

      expect(container.read(profileNotifierProvider).value!.photoUrl, isNull);
      expect(auth.restoreCalls, restoresBefore);
    });

    test('remove clears the photo url and refreshes the session', () async {
      fake = FakeProfileRepository(profile: teacherProfile(photoUrl: '/users/12/photo?v=old'));
      final container = await loadedContainer(fake, auth);
      final restoresBefore = auth.restoreCalls;

      await container.read(profileNotifierProvider.notifier).removePhoto();

      expect(fake.removeCalls, 1);
      expect(container.read(profileNotifierProvider).value!.photoUrl, isNull);
      expect(auth.restoreCalls, restoresBefore + 1);
    });

    test('a failed remove keeps the photo', () async {
      fake = FakeProfileRepository(profile: teacherProfile(photoUrl: '/users/12/photo?v=old'))
        ..failRemoveWith = Failure.network();
      final container = await loadedContainer(fake, auth);

      await expectLater(container.read(profileNotifierProvider.notifier).removePhoto(), throwsA(isA<Failure>()));

      expect(container.read(profileNotifierProvider).value!.photoUrl, '/users/12/photo?v=old');
    });
  });
}
