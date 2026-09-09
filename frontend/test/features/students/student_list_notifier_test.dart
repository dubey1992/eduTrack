import 'package:edutrack_app/features/students/application/student_list_notifier.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_student_repository.dart';

Student _student({int id = 1, StudentStatus status = StudentStatus.active}) {
  return Student(
    id: id,
    schoolId: 1,
    schoolName: 'Sunrise Public School',
    classSectionId: 1,
    classSectionName: 'Grade 8 A',
    admissionNumber: 'STU-000$id',
    firstName: 'Arjun',
    lastName: 'Kumar',
    name: 'Arjun Kumar',
    rollNumber: '12',
    guardianName: 'Raj Kumar',
    guardianMobile: '9876543210',
    address: null,
    status: status,
  );
}

void main() {
  ProviderContainer makeContainer(FakeStudentRepository fake) {
    return ProviderContainer(overrides: [studentRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the initial student list', () async {
    final container = makeContainer(FakeStudentRepository(students: [_student()]));
    addTearDown(container.dispose);

    final result = await container.read(studentListNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.admissionNumber, 'STU-0001');
  });

  test('createStudent() adds the new student to the list', () async {
    final container = makeContainer(FakeStudentRepository());
    addTearDown(container.dispose);
    await container.read(studentListNotifierProvider.future);

    await container
        .read(studentListNotifierProvider.notifier)
        .createStudent(
          classSectionId: 1,
          admissionNumber: 'STU-0042',
          firstName: 'Aarav',
          lastName: 'Mehta',
          guardianName: 'Neha Mehta',
        );

    final state = container.read(studentListNotifierProvider).value;
    expect(state!.items, hasLength(1));
    expect(state.items.first.admissionNumber, 'STU-0042');
  });

  test('setActive() updates that students status in place', () async {
    final container = makeContainer(FakeStudentRepository(students: [_student()]));
    addTearDown(container.dispose);
    final students = await container.read(studentListNotifierProvider.future);

    await container.read(studentListNotifierProvider.notifier).setActive(students.items.first, false);

    final state = container.read(studentListNotifierProvider).value;
    expect(state!.items.first.status, StudentStatus.inactive);
  });

  test('goToPage() and setPerPage() page through the list', () async {
    final container = makeContainer(FakeStudentRepository(students: [for (var i = 1; i <= 25; i++) _student(id: i)]));
    addTearDown(container.dispose);
    await container.read(studentListNotifierProvider.future);

    await container.read(studentListNotifierProvider.notifier).goToPage(2);
    var state = container.read(studentListNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(5));

    await container.read(studentListNotifierProvider.notifier).setPerPage(50);
    state = container.read(studentListNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.items, hasLength(25));
  });
}
