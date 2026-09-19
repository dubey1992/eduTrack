import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/permissions/application/permissions_notifier.dart';
import 'package:edutrack_app/features/permissions/data/models/permissions_matrix.dart';
import 'package:edutrack_app/features/permissions/data/permissions_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_permissions_repository.dart';

ProviderContainer makeContainer(FakePermissionsRepository fake) {
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [permissionsRepositoryProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  return container;
}

/// The platform's matrix: loaded once, replaced by whatever a save or a
/// reset hands back, and left alone when either of those fails.
void main() {
  test('loads the matrix from the API', () async {
    final container = makeContainer(FakePermissionsRepository());

    final matrix = await container.read(permissionsNotifierProvider.future);

    expect(matrix.roles.map((r) => r.value), ['SCHOOL_ADMIN', 'HOD', 'TEACHER']);
    expect(matrix.modules.map((m) => m.value), ['students', 'attendance', 'timetable']);
    expect(matrix.levelOf('TEACHER', 'students'), PermissionLevel.view);
    expect(matrix.defaultOf('TEACHER', 'students'), PermissionLevel.view);
    expect(matrix.canEdit, isTrue);
  });

  test('a failed load is the error state', () async {
    final fake = FakePermissionsRepository(
      failGetWith: const Failure(code: 'FORBIDDEN', message: 'You are not allowed to do this.'),
    );
    final container = makeContainer(fake);

    await expectLater(container.read(permissionsNotifierProvider.future), throwsA(isA<Failure>()));
    expect(container.read(permissionsNotifierProvider).hasError, isTrue);
  });

  test('load() asks the API again', () async {
    final fake = FakePermissionsRepository();
    final container = makeContainer(fake);
    await container.read(permissionsNotifierProvider.future);
    expect(fake.getCalls, 1);

    fake.matrix = permissionsMatrix(canEdit: false);
    await container.read(permissionsNotifierProvider.notifier).load();

    expect(fake.getCalls, 2);
    expect(container.read(permissionsNotifierProvider).value!.canEdit, isFalse);
  });

  test('save sends only the changed cells and replaces the matrix with what came back', () async {
    final fake = FakePermissionsRepository();
    final container = makeContainer(fake);
    await container.read(permissionsNotifierProvider.future);

    await container.read(permissionsNotifierProvider.notifier).save({
      'TEACHER': {'students': PermissionLevel.manage},
      'HOD': {'attendance': PermissionLevel.view},
    });

    expect(fake.lastSave, {
      'TEACHER': {'students': 'manage'},
      'HOD': {'attendance': 'view'},
    });
    final matrix = container.read(permissionsNotifierProvider).value!;
    expect(matrix.levelOf('TEACHER', 'students'), PermissionLevel.manage);
    expect(matrix.levelOf('HOD', 'attendance'), PermissionLevel.view);
    // Untouched cells are as they were.
    expect(matrix.levelOf('SCHOOL_ADMIN', 'students'), PermissionLevel.manage);
    expect(matrix.defaultOf('TEACHER', 'students'), PermissionLevel.view);
  });

  test('a refused save throws and leaves the loaded matrix in place', () async {
    final fake = FakePermissionsRepository(
      failSaveWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'HOD Reports cannot be set to manage for a Teacher.',
        details: {
          'errors': {
            'matrix': ['HOD Reports cannot be set to manage for a Teacher.'],
          },
        },
      ),
    );
    final container = makeContainer(fake);
    await container.read(permissionsNotifierProvider.future);

    await expectLater(
      container.read(permissionsNotifierProvider.notifier).save({
        'TEACHER': {'students': PermissionLevel.manage},
      }),
      throwsA(
        isA<Failure>().having((f) => f.validationErrors['matrix'], 'matrix error', [
          'HOD Reports cannot be set to manage for a Teacher.',
        ]),
      ),
    );

    final state = container.read(permissionsNotifierProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
    expect(state.value!.levelOf('TEACHER', 'students'), PermissionLevel.view);
  });

  test('a save the server forbids throws with its reason', () async {
    final fake = FakePermissionsRepository(
      matrix: permissionsMatrix(canEdit: false),
      failSaveWith: const Failure(code: 'FORBIDDEN', message: 'Only the Super Admin can change the matrix.'),
    );
    final container = makeContainer(fake);
    await container.read(permissionsNotifierProvider.future);

    await expectLater(
      container.read(permissionsNotifierProvider.notifier).save({
        'TEACHER': {'students': PermissionLevel.manage},
      }),
      throwsA(isA<Failure>().having((f) => f.code, 'code', 'FORBIDDEN')),
    );
    expect(container.read(permissionsNotifierProvider).hasValue, isTrue);
  });

  test('reset calls the API and takes the defaults back', () async {
    final fake = FakePermissionsRepository(
      matrix: permissionsMatrix(
        matrix: {
          ...permissionDefaults,
          'TEACHER': {...permissionDefaults['TEACHER']!, 'students': PermissionLevel.manage},
        },
      ),
    );
    final container = makeContainer(fake);
    await container.read(permissionsNotifierProvider.future);
    expect(container.read(permissionsNotifierProvider).value!.levelOf('TEACHER', 'students'), PermissionLevel.manage);

    await container.read(permissionsNotifierProvider.notifier).reset();

    expect(fake.resetCalls, 1);
    expect(container.read(permissionsNotifierProvider).value!.levelOf('TEACHER', 'students'), PermissionLevel.view);
  });

  test('a refused reset throws and keeps the matrix', () async {
    final fake = FakePermissionsRepository(
      failResetWith: const Failure(code: 'FORBIDDEN', message: 'Only the Super Admin can change the matrix.'),
    );
    final container = makeContainer(fake);
    await container.read(permissionsNotifierProvider.future);

    await expectLater(container.read(permissionsNotifierProvider.notifier).reset(), throwsA(isA<Failure>()));
    expect(container.read(permissionsNotifierProvider).hasValue, isTrue);
  });
}
