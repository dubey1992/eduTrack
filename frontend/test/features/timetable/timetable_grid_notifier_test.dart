import 'package:edutrack_app/features/timetable/application/timetable_grid_notifier.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_timetable_repository.dart';

const _entry = TimetableEntry(
  id: 1,
  schoolId: 1,
  classSectionId: 10,
  classSectionName: 'Grade 8 A',
  periodId: 1,
  periodNumber: 1,
  dayOfWeek: DayOfWeek.monday,
  subjectId: 5,
  subjectName: 'Mathematics',
  teacherId: 20,
  teacherName: 'Priya Sharma',
);

void main() {
  ProviderContainer makeContainer(FakeTimetableRepository fake) {
    return ProviderContainer(overrides: [timetableRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads a class sections grid', () async {
    final fake = FakeTimetableRepository(entries: [_entry]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    final result = await container.read(timetableGridProvider(const TimetableGridParams.forClassSection(10)).future);

    expect(result, hasLength(1));
  });

  test('build() loads a teachers own schedule', () async {
    final otherClassEntry = TimetableEntry(
      id: 2,
      schoolId: 1,
      classSectionId: 11,
      classSectionName: 'Grade 8 B',
      periodId: 2,
      periodNumber: 2,
      dayOfWeek: DayOfWeek.tuesday,
      subjectId: 5,
      subjectName: 'Mathematics',
      teacherId: 20,
      teacherName: 'Priya Sharma',
    );
    final fake = FakeTimetableRepository(entries: [_entry, otherClassEntry]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    final result = await container.read(timetableGridProvider(const TimetableGridParams.forTeacher(20)).future);

    expect(result, hasLength(2));
  });

  test('upsertCell() creates a new entry and refreshes the grid', () async {
    final fake = FakeTimetableRepository();
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    const params = TimetableGridParams.forClassSection(10);
    await container.read(timetableGridProvider(params).future);

    await container
        .read(timetableGridProvider(params).notifier)
        .upsertCell(periodId: 1, dayOfWeek: DayOfWeek.monday, subjectId: 5, teacherId: 20);

    expect(fake.lastUpsertPayload, isNotNull);
    final state = container.read(timetableGridProvider(params)).value!;
    expect(state, hasLength(1));
  });

  test('upsertCell() does nothing for a teacher-scoped (read-only) grid', () async {
    final fake = FakeTimetableRepository();
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    const params = TimetableGridParams.forTeacher(20);
    await container.read(timetableGridProvider(params).future);

    await container
        .read(timetableGridProvider(params).notifier)
        .upsertCell(periodId: 1, dayOfWeek: DayOfWeek.monday, subjectId: 5, teacherId: 20);

    expect(fake.lastUpsertPayload, isNull);
  });

  test('deleteCell() removes the entry and refreshes the grid', () async {
    final fake = FakeTimetableRepository(entries: [_entry]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    const params = TimetableGridParams.forClassSection(10);
    await container.read(timetableGridProvider(params).future);

    await container.read(timetableGridProvider(params).notifier).deleteCell(_entry);

    expect(fake.lastDeletedId, 1);
    final state = container.read(timetableGridProvider(params)).value!;
    expect(state, isEmpty);
  });
}
