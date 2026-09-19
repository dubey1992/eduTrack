import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/module_settings/application/module_settings_notifier.dart';
import 'package:edutrack_app/features/module_settings/data/module_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_module_settings_repository.dart';

ProviderContainer makeContainer(FakeModuleSettingsRepository fake) {
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [moduleSettingsRepositoryProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  return container;
}

/// One school's modules: loaded for the school the family key names,
/// each saved row swapped into the list, and left alone when a save fails.
void main() {
  test('loads the modules for the school asked for', () async {
    final fake = FakeModuleSettingsRepository();
    final container = makeContainer(fake);

    final rows = await container.read(moduleSettingsNotifierProvider(7).future);

    expect(fake.lastListSchoolId, 7);
    expect(rows.map((r) => r.module), ['students', 'attendance', 'payroll', 'timetable']);
    expect(rows.first.switchable, isFalse);
    expect(rows[1].hasSettings, isTrue);
  });

  test('a school admin asks with no school id', () async {
    final fake = FakeModuleSettingsRepository();
    final container = makeContainer(fake);

    await container.read(moduleSettingsNotifierProvider(null).future);

    expect(fake.listCalls, 1);
    expect(fake.lastListSchoolId, isNull);
  });

  test('a failed load is the error state', () async {
    final fake = FakeModuleSettingsRepository(
      failListWith: const Failure(code: 'VALIDATION_ERROR', message: 'The school id field is required.'),
    );
    final container = makeContainer(fake);

    await expectLater(container.read(moduleSettingsNotifierProvider(null).future), throwsA(isA<Failure>()));
    expect(container.read(moduleSettingsNotifierProvider(null)).hasError, isTrue);
  });

  test('load() asks the API again', () async {
    final fake = FakeModuleSettingsRepository();
    final container = makeContainer(fake);
    await container.read(moduleSettingsNotifierProvider(1).future);
    expect(fake.listCalls, 1);

    fake.rows = [moduleSetting(module: 'timetable', label: 'Timetable')];
    await container.read(moduleSettingsNotifierProvider(1).notifier).load();

    expect(fake.listCalls, 2);
    expect(container.read(moduleSettingsNotifierProvider(1)).value!.map((r) => r.module), ['timetable']);
  });

  test('moving the school switch sends that switch alone and swaps the row in', () async {
    final fake = FakeModuleSettingsRepository();
    final container = makeContainer(fake);
    await container.read(moduleSettingsNotifierProvider(1).future);

    await container.read(moduleSettingsNotifierProvider(1).notifier).updateSwitch('attendance', schoolEnabled: false);

    expect(fake.lastUpdate, {
      'module': 'attendance',
      'school_id': 1,
      'platform_enabled': null,
      'school_enabled': false,
      'settings': null,
    });
    final rows = container.read(moduleSettingsNotifierProvider(1)).value!;
    final attendance = rows.firstWhere((r) => r.module == 'attendance');
    expect(attendance.schoolEnabled, isFalse);
    expect(attendance.enabled, isFalse);
    expect(attendance.updatedByName, 'Anita Sharma');
    // The other rows are exactly as they were.
    expect(rows.map((r) => r.module), ['students', 'attendance', 'payroll', 'timetable']);
    expect(rows.firstWhere((r) => r.module == 'payroll').updatedByName, isNull);
  });

  test('moving the platform switch sends that switch alone', () async {
    final fake = FakeModuleSettingsRepository();
    final container = makeContainer(fake);
    await container.read(moduleSettingsNotifierProvider(1).future);

    await container.read(moduleSettingsNotifierProvider(1).notifier).updateSwitch('timetable', platformEnabled: false);

    expect(fake.lastUpdate!['platform_enabled'], isFalse);
    expect(fake.lastUpdate!['school_enabled'], isNull);
    expect(fake.lastUpdate!['settings'], isNull);
    final timetable = container
        .read(moduleSettingsNotifierProvider(1))
        .value!
        .firstWhere((r) => r.module == 'timetable');
    expect(timetable.platformEnabled, isFalse);
    expect(timetable.enabled, isFalse);
  });

  test('saving settings sends the settings alone, for that module', () async {
    final fake = FakeModuleSettingsRepository();
    final container = makeContainer(fake);
    await container.read(moduleSettingsNotifierProvider(1).future);

    await container.read(moduleSettingsNotifierProvider(1).notifier).saveSettings('attendance', {'late_days': 3});

    expect(fake.lastUpdate, {
      'module': 'attendance',
      'school_id': 1,
      'platform_enabled': null,
      'school_enabled': null,
      'settings': {'late_days': 3},
    });
    final attendance = container
        .read(moduleSettingsNotifierProvider(1))
        .value!
        .firstWhere((r) => r.module == 'attendance');
    expect(attendance.settings['late_days'], 3);
    expect(attendance.valueOf(lateDaysField), 3);
  });

  test('a refused update throws and leaves the loaded list in place', () async {
    final fake = FakeModuleSettingsRepository(
      failUpdateWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'Only the Super Admin can grant or withdraw a module.',
        details: {
          'errors': {
            'platform_enabled': ['Only the Super Admin can grant or withdraw a module.'],
          },
        },
      ),
    );
    final container = makeContainer(fake);
    await container.read(moduleSettingsNotifierProvider(null).future);

    await expectLater(
      container.read(moduleSettingsNotifierProvider(null).notifier).updateSwitch('attendance', platformEnabled: false),
      throwsA(
        isA<Failure>().having((f) => f.validationErrors['platform_enabled'], 'platform error', [
          'Only the Super Admin can grant or withdraw a module.',
        ]),
      ),
    );

    final state = container.read(moduleSettingsNotifierProvider(null));
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
    expect(state.value!.firstWhere((r) => r.module == 'attendance').platformEnabled, isTrue);
  });
}
