import 'package:edutrack_app/features/subjects/application/subject_list_notifier.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_subject_repository.dart';

void main() {
  ProviderContainer makeContainer(FakeSubjectRepository fake) {
    return ProviderContainer(overrides: [subjectRepositoryProvider.overrideWithValue(fake)]);
  }

  test('createSubject() adds the new subject and returns to page 1', () async {
    final container = makeContainer(FakeSubjectRepository());
    addTearDown(container.dispose);
    await container.read(subjectListNotifierProvider.future);

    await container
        .read(subjectListNotifierProvider.notifier)
        .createSubject(
          schoolId: 1,
          departmentId: 2,
          code: 'MAT',
          name: 'Mathematics',
          minClassLevel: 7,
          maxClassLevel: 10,
          leadTeacherId: 9,
        );

    final state = container.read(subjectListNotifierProvider).value;
    expect(state!.items, hasLength(1));
    expect(state.items.first.code, 'MAT');
    expect(state.items.first.minClassLevel, 7);
    expect(state.items.first.maxClassLevel, 10);
  });

  test('updateSubject() saves the changes in place', () async {
    final container = makeContainer(FakeSubjectRepository());
    addTearDown(container.dispose);
    await container.read(subjectListNotifierProvider.future);
    await container
        .read(subjectListNotifierProvider.notifier)
        .createSubject(
          schoolId: 1,
          departmentId: 2,
          code: 'MAT',
          name: 'Mathematics',
          minClassLevel: 1,
          maxClassLevel: 5,
        );
    final subject = container.read(subjectListNotifierProvider).value!.items.first;

    await container
        .read(subjectListNotifierProvider.notifier)
        .updateSubject(subject, name: 'Advanced Mathematics', maxClassLevel: 8);

    final state = container.read(subjectListNotifierProvider).value;
    expect(state!.items.first.name, 'Advanced Mathematics');
    expect(state.items.first.maxClassLevel, 8);
  });

  test('deleteSubject() removes the subject from the list', () async {
    final container = makeContainer(FakeSubjectRepository());
    addTearDown(container.dispose);
    await container.read(subjectListNotifierProvider.future);
    await container
        .read(subjectListNotifierProvider.notifier)
        .createSubject(
          schoolId: 1,
          departmentId: 2,
          code: 'MAT',
          name: 'Mathematics',
          minClassLevel: 1,
          maxClassLevel: 5,
        );
    final subject = container.read(subjectListNotifierProvider).value!.items.first;

    await container.read(subjectListNotifierProvider.notifier).deleteSubject(subject);

    final state = container.read(subjectListNotifierProvider).value;
    expect(state!.items, isEmpty);
  });

  test('goToPage() and setPerPage() page through the list', () async {
    final container = makeContainer(
      FakeSubjectRepository(
        subjects: [
          for (var i = 1; i <= 25; i++)
            Subject(
              id: i,
              schoolId: 1,
              schoolName: 'Sunrise Public School',
              departmentId: 2,
              departmentName: 'Science',
              code: 'SUB$i',
              name: 'Subject $i',
              minClassLevel: 1,
              maxClassLevel: 5,
              leadTeacherId: null,
              leadTeacherName: null,
            ),
        ],
      ),
    );
    addTearDown(container.dispose);
    await container.read(subjectListNotifierProvider.future);

    await container.read(subjectListNotifierProvider.notifier).goToPage(2);
    var state = container.read(subjectListNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(5));

    await container.read(subjectListNotifierProvider.notifier).setPerPage(50);
    state = container.read(subjectListNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.items, hasLength(25));
  });
}
