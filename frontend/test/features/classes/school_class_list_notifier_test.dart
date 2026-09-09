import 'package:edutrack_app/features/classes/application/school_class_list_notifier.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_class_repository.dart';

void main() {
  ProviderContainer makeContainer(FakeSchoolClassRepository fake) {
    return ProviderContainer(overrides: [schoolClassRepositoryProvider.overrideWithValue(fake)]);
  }

  test('createClass() adds the new class and returns to page 1', () async {
    final container = makeContainer(FakeSchoolClassRepository());
    addTearDown(container.dispose);
    await container.read(schoolClassListNotifierProvider.future);

    await container
        .read(schoolClassListNotifierProvider.notifier)
        .createClass(schoolId: 1, academicYearId: 3, name: 'Grade 8', level: 8);

    final state = container.read(schoolClassListNotifierProvider).value;
    expect(state!.items, hasLength(1));
    expect(state.items.first.name, 'Grade 8');
    expect(state.items.first.sections, isEmpty);
  });

  test('updateClass() saves the changes in place', () async {
    final container = makeContainer(FakeSchoolClassRepository());
    addTearDown(container.dispose);
    await container.read(schoolClassListNotifierProvider.future);
    await container
        .read(schoolClassListNotifierProvider.notifier)
        .createClass(schoolId: 1, academicYearId: 3, name: 'Grade 8', level: 8);
    final schoolClass = container.read(schoolClassListNotifierProvider).value!.items.first;

    await container.read(schoolClassListNotifierProvider.notifier).updateClass(schoolClass, name: 'Grade 8A', level: 8);

    final state = container.read(schoolClassListNotifierProvider).value;
    expect(state!.items.first.name, 'Grade 8A');
  });

  test('addSection() attaches a new section to its class', () async {
    final container = makeContainer(FakeSchoolClassRepository());
    addTearDown(container.dispose);
    await container.read(schoolClassListNotifierProvider.future);
    await container
        .read(schoolClassListNotifierProvider.notifier)
        .createClass(schoolId: 1, academicYearId: 3, name: 'Grade 8', level: 8);
    final schoolClass = container.read(schoolClassListNotifierProvider).value!.items.first;

    await container
        .read(schoolClassListNotifierProvider.notifier)
        .addSection(schoolClass: schoolClass, name: 'A', roomNumber: 'Room 204', classTeacherId: 7);

    final state = container.read(schoolClassListNotifierProvider).value;
    expect(state!.items.first.sections, hasLength(1));
    expect(state.items.first.sections.first.name, 'A');
    expect(state.items.first.sections.first.roomNumber, 'Room 204');
  });

  test('updateSection() saves the changes in place', () async {
    final container = makeContainer(FakeSchoolClassRepository());
    addTearDown(container.dispose);
    await container.read(schoolClassListNotifierProvider.future);
    await container
        .read(schoolClassListNotifierProvider.notifier)
        .createClass(schoolId: 1, academicYearId: 3, name: 'Grade 8', level: 8);
    var schoolClass = container.read(schoolClassListNotifierProvider).value!.items.first;
    await container
        .read(schoolClassListNotifierProvider.notifier)
        .addSection(schoolClass: schoolClass, name: 'A', roomNumber: 'Room 204');
    final section = container.read(schoolClassListNotifierProvider).value!.items.first.sections.first;

    await container
        .read(schoolClassListNotifierProvider.notifier)
        .updateSection(section, roomNumber: 'Room 310', classTeacherId: 7);

    final state = container.read(schoolClassListNotifierProvider).value;
    expect(state!.items.first.sections.first.roomNumber, 'Room 310');
    expect(state.items.first.sections.first.classTeacherId, 7);
  });

  test('deleteSection() removes the section from its class', () async {
    final container = makeContainer(FakeSchoolClassRepository());
    addTearDown(container.dispose);
    await container.read(schoolClassListNotifierProvider.future);
    await container
        .read(schoolClassListNotifierProvider.notifier)
        .createClass(schoolId: 1, academicYearId: 3, name: 'Grade 8', level: 8);
    var schoolClass = container.read(schoolClassListNotifierProvider).value!.items.first;
    await container.read(schoolClassListNotifierProvider.notifier).addSection(schoolClass: schoolClass, name: 'A');
    final section = container.read(schoolClassListNotifierProvider).value!.items.first.sections.first;

    await container.read(schoolClassListNotifierProvider.notifier).deleteSection(section);

    final state = container.read(schoolClassListNotifierProvider).value;
    expect(state!.items.first.sections, isEmpty);
  });

  test('deleteClass() removes the class from the list', () async {
    final container = makeContainer(FakeSchoolClassRepository());
    addTearDown(container.dispose);
    await container.read(schoolClassListNotifierProvider.future);
    await container
        .read(schoolClassListNotifierProvider.notifier)
        .createClass(schoolId: 1, academicYearId: 3, name: 'Grade 8', level: 8);
    final schoolClass = container.read(schoolClassListNotifierProvider).value!.items.first;

    await container.read(schoolClassListNotifierProvider.notifier).deleteClass(schoolClass);

    final state = container.read(schoolClassListNotifierProvider).value;
    expect(state!.items, isEmpty);
  });

  test('goToPage() and setPerPage() page through the list', () async {
    final container = makeContainer(FakeSchoolClassRepository());
    addTearDown(container.dispose);
    for (var i = 1; i <= 25; i++) {
      await container
          .read(schoolClassListNotifierProvider.notifier)
          .createClass(schoolId: 1, academicYearId: 3, name: 'Grade $i', level: i.clamp(1, 12));
    }

    await container.read(schoolClassListNotifierProvider.notifier).goToPage(2);
    var state = container.read(schoolClassListNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(5));

    await container.read(schoolClassListNotifierProvider.notifier).setPerPage(50);
    state = container.read(schoolClassListNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.items, hasLength(25));
  });
}
