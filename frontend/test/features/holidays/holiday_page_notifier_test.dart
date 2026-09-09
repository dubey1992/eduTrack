import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/holidays/application/holiday_page_notifier.dart';
import 'package:edutrack_app/features/holidays/data/holiday_repository.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_holiday_repository.dart';

const _diwali = Holiday(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Diwali Break',
  type: HolidayType.religious,
  startDate: '2026-11-09',
  endDate: '2026-11-11',
  days: 3,
);

const _independence = Holiday(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Independence Day',
  type: HolidayType.national,
  startDate: '2026-08-15',
  endDate: '2026-08-15',
  days: 1,
);

void main() {
  ProviderContainer makeContainer(FakeHolidayRepository fake) {
    final container = ProviderContainer(overrides: [holidayRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    return container;
  }

  test('build() loads the first page ordered by date', () async {
    final container = makeContainer(FakeHolidayRepository(holidays: [_diwali, _independence]));

    final result = await container.read(holidayPageNotifierProvider.future);

    expect(result.items.map((h) => h.name), ['Independence Day', 'Diwali Break']);
    expect(result.total, 2);
  });

  test('createHoliday() adds the holiday and returns to page 1', () async {
    final fake = FakeHolidayRepository();
    final container = makeContainer(fake);
    await container.read(holidayPageNotifierProvider.future);

    await container
        .read(holidayPageNotifierProvider.notifier)
        .createHoliday(
          schoolId: null,
          name: 'Sports Day',
          type: HolidayType.schoolEvent,
          startDate: '2026-12-04',
          endDate: '2026-12-04',
        );

    final state = container.read(holidayPageNotifierProvider).value!;
    expect(state.items.single.name, 'Sports Day');
    expect(state.items.single.days, 1);
    expect(fake.lastCreatePayload!['type'], 'school_event');
  });

  test('updateHoliday() saves the changes in place', () async {
    final container = makeContainer(FakeHolidayRepository(holidays: [_diwali]));
    final page = await container.read(holidayPageNotifierProvider.future);

    await container
        .read(holidayPageNotifierProvider.notifier)
        .updateHoliday(page.items.first, name: 'Diwali', endDate: '2026-11-13');

    final state = container.read(holidayPageNotifierProvider).value!;
    expect(state.items.single.name, 'Diwali');
    expect(state.items.single.endDate, '2026-11-13');
    expect(state.items.single.days, 5);
  });

  test('deleteHoliday() removes the holiday', () async {
    final fake = FakeHolidayRepository(holidays: [_diwali, _independence]);
    final container = makeContainer(fake);
    await container.read(holidayPageNotifierProvider.future);

    await container.read(holidayPageNotifierProvider.notifier).deleteHoliday(_diwali);

    expect(fake.lastDeletedId, 1);
    expect(container.read(holidayPageNotifierProvider).value!.items.map((h) => h.id), [2]);
  });

  test('setDateWindow() narrows the list and resets to page 1', () async {
    final fake = FakeHolidayRepository(holidays: [_diwali, _independence]);
    final container = makeContainer(fake);
    await container.read(holidayPageNotifierProvider.future);
    await container.read(holidayPageNotifierProvider.notifier).goToPage(2);

    await container.read(holidayPageNotifierProvider.notifier).setDateWindow(from: '2026-11-01', to: '2026-11-30');

    expect(fake.lastListRequest!['page'], 1);
    expect(container.read(holidayPageNotifierProvider).value!.items.map((h) => h.name), ['Diwali Break']);
  });

  test('a failed create surfaces the Failure and leaves the list untouched', () async {
    final fake = FakeHolidayRepository(
      holidays: [_diwali],
      failCreateWith: const Failure(code: 'HOLIDAY_OVERLAP', message: 'These dates overlap "Diwali Break".'),
    );
    final container = makeContainer(fake);
    await container.read(holidayPageNotifierProvider.future);

    await expectLater(
      container
          .read(holidayPageNotifierProvider.notifier)
          .createHoliday(
            schoolId: null,
            name: 'X',
            type: HolidayType.national,
            startDate: '2026-11-10',
            endDate: '2026-11-10',
          ),
      throwsA(isA<Failure>().having((f) => f.code, 'code', 'HOLIDAY_OVERLAP')),
    );
    expect(container.read(holidayPageNotifierProvider).value!.items, hasLength(1));
  });
}
