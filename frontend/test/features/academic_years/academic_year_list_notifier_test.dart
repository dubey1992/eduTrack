import 'package:edutrack_app/features/academic_years/application/academic_year_list_notifier.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';

AcademicYear _year({int id = 1, bool isCurrent = false}) {
  return AcademicYear(
    id: id,
    schoolId: 1,
    schoolName: 'Sunrise Public School',
    name: '2025-26',
    startDate: DateTime(2025, 4, 1),
    endDate: DateTime(2026, 3, 31),
    isCurrent: isCurrent,
  );
}

void main() {
  ProviderContainer makeContainer(FakeAcademicYearRepository fake) {
    return ProviderContainer(overrides: [academicYearRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the initial page of academic years', () async {
    final container = makeContainer(FakeAcademicYearRepository(years: [_year()]));
    addTearDown(container.dispose);

    final result = await container.read(academicYearListNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.name, '2025-26');
  });

  test('createAcademicYear() adds the new year and returns to page 1', () async {
    final container = makeContainer(FakeAcademicYearRepository());
    addTearDown(container.dispose);
    await container.read(academicYearListNotifierProvider.future);

    await container
        .read(academicYearListNotifierProvider.notifier)
        .createAcademicYear(
          schoolId: 1,
          name: '2026-27',
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2027, 3, 31),
          isCurrent: true,
        );

    final state = container.read(academicYearListNotifierProvider).value;
    expect(state!.items, hasLength(1));
    expect(state.items.first.isCurrent, isTrue);
  });

  test('updateAcademicYear() saves the changes in place', () async {
    final container = makeContainer(FakeAcademicYearRepository(years: [_year()]));
    addTearDown(container.dispose);
    final page = await container.read(academicYearListNotifierProvider.future);

    await container
        .read(academicYearListNotifierProvider.notifier)
        .updateAcademicYear(page.items.first, name: '2025-26 (Revised)', endDate: DateTime(2026, 4, 15));

    final state = container.read(academicYearListNotifierProvider).value;
    expect(state!.items.first.name, '2025-26 (Revised)');
    expect(state.items.first.endDate, DateTime(2026, 4, 15));
  });

  test('setCurrent() unsets every other year for that school', () async {
    final container = makeContainer(FakeAcademicYearRepository(years: [_year(isCurrent: true)]));
    addTearDown(container.dispose);
    await container.read(academicYearListNotifierProvider.future);

    await container
        .read(academicYearListNotifierProvider.notifier)
        .createAcademicYear(
          schoolId: 1,
          name: '2026-27',
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2027, 3, 31),
          isCurrent: false,
        );
    final newYear = container.read(academicYearListNotifierProvider).value!.items.last;

    await container.read(academicYearListNotifierProvider.notifier).setCurrent(newYear);

    final state = container.read(academicYearListNotifierProvider).value!;
    expect(state.items.where((y) => y.isCurrent), hasLength(1));
    expect(state.items.firstWhere((y) => y.id == newYear.id).isCurrent, isTrue);
  });

  test('deleteAcademicYear() removes the year from the list', () async {
    final container = makeContainer(FakeAcademicYearRepository(years: [_year()]));
    addTearDown(container.dispose);
    final page = await container.read(academicYearListNotifierProvider.future);

    await container.read(academicYearListNotifierProvider.notifier).deleteAcademicYear(page.items.first);

    final state = container.read(academicYearListNotifierProvider).value;
    expect(state!.items, isEmpty);
  });

  test('goToPage() and setPerPage() page through the list', () async {
    final container = makeContainer(FakeAcademicYearRepository(years: [for (var i = 1; i <= 25; i++) _year(id: i)]));
    addTearDown(container.dispose);
    await container.read(academicYearListNotifierProvider.future);

    await container.read(academicYearListNotifierProvider.notifier).goToPage(2);
    var state = container.read(academicYearListNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(5));

    await container.read(academicYearListNotifierProvider.notifier).setPerPage(50);
    state = container.read(academicYearListNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.items, hasLength(25));
  });
}
