import 'package:edutrack_app/features/timetable/application/period_list_notifier.dart';
import 'package:edutrack_app/features/timetable/data/models/period.dart';
import 'package:edutrack_app/features/timetable/data/period_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_period_repository.dart';

const _period = Period(id: 1, schoolId: 1, periodNumber: 1, startTime: '08:30', endTime: '09:15');

void main() {
  ProviderContainer makeContainer(FakePeriodRepository fake) {
    return ProviderContainer(overrides: [periodRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the periods for the given school', () async {
    final fake = FakePeriodRepository(periods: [_period]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    final result = await container.read(periodListNotifierProvider(1).future);

    expect(result, hasLength(1));
    expect(result.first.periodNumber, 1);
  });

  test('create() adds a period and refreshes the list', () async {
    final fake = FakePeriodRepository();
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(periodListNotifierProvider(1).future);

    await container
        .read(periodListNotifierProvider(1).notifier)
        .create(periodNumber: 1, startTime: '08:30', endTime: '09:15');

    final state = container.read(periodListNotifierProvider(1)).value!;
    expect(state, hasLength(1));
  });

  test('editPeriod() updates the period and refreshes the list', () async {
    final fake = FakePeriodRepository(periods: [_period]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(periodListNotifierProvider(1).future);

    await container.read(periodListNotifierProvider(1).notifier).editPeriod(_period, startTime: '08:00');

    final state = container.read(periodListNotifierProvider(1)).value!;
    expect(state.first.startTime, '08:00');
  });

  test('delete() removes the period and refreshes the list', () async {
    final fake = FakePeriodRepository(periods: [_period]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(periodListNotifierProvider(1).future);

    await container.read(periodListNotifierProvider(1).notifier).delete(_period);

    expect(fake.lastDeletedId, 1);
    final state = container.read(periodListNotifierProvider(1)).value!;
    expect(state, isEmpty);
  });
}
