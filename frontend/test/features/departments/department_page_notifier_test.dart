import 'package:edutrack_app/features/departments/application/department_list_notifier.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_department_repository.dart';

const _department = Department(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: null,
  hodName: null,
);

void main() {
  ProviderContainer makeContainer(FakeDepartmentRepository fake) {
    return ProviderContainer(overrides: [departmentRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the initial page of departments', () async {
    final container = makeContainer(FakeDepartmentRepository(departments: [_department]));
    addTearDown(container.dispose);

    final result = await container.read(departmentPageNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.name, 'Mathematics');
  });

  test('createDepartment() adds the new department and returns to page 1', () async {
    final container = makeContainer(FakeDepartmentRepository());
    addTearDown(container.dispose);
    await container.read(departmentPageNotifierProvider.future);

    await container
        .read(departmentPageNotifierProvider.notifier)
        .createDepartment(schoolId: 1, name: 'Science', hodUserId: 5);

    final state = container.read(departmentPageNotifierProvider).value;
    expect(state!.items, hasLength(1));
    expect(state.items.first.name, 'Science');
    expect(state.items.first.hodUserId, 5);
  });

  test('updateDepartment() saves the changes in place', () async {
    final container = makeContainer(FakeDepartmentRepository(departments: [_department]));
    addTearDown(container.dispose);
    final page = await container.read(departmentPageNotifierProvider.future);

    await container
        .read(departmentPageNotifierProvider.notifier)
        .updateDepartment(page.items.first, name: 'Advanced Mathematics', hodUserId: 9);

    final state = container.read(departmentPageNotifierProvider).value;
    expect(state!.items.first.name, 'Advanced Mathematics');
    expect(state.items.first.hodUserId, 9);
  });

  test('deleteDepartment() removes the department from the list', () async {
    final container = makeContainer(FakeDepartmentRepository(departments: [_department]));
    addTearDown(container.dispose);
    final page = await container.read(departmentPageNotifierProvider.future);

    await container.read(departmentPageNotifierProvider.notifier).deleteDepartment(page.items.first);

    final state = container.read(departmentPageNotifierProvider).value;
    expect(state!.items, isEmpty);
  });

  test('creating a department also invalidates the unpaginated picker provider', () async {
    final container = makeContainer(FakeDepartmentRepository());
    addTearDown(container.dispose);
    await container.read(departmentListNotifierProvider.future);
    await container.read(departmentPageNotifierProvider.future);

    await container
        .read(departmentPageNotifierProvider.notifier)
        .createDepartment(schoolId: 1, name: 'Science', hodUserId: null);

    final pickerState = await container.read(departmentListNotifierProvider.future);
    expect(pickerState, hasLength(1));
    expect(pickerState.first.name, 'Science');
  });

  test('goToPage() and setPerPage() page through the list', () async {
    final container = makeContainer(
      FakeDepartmentRepository(
        departments: [
          for (var i = 1; i <= 25; i++)
            Department(
              id: i,
              schoolId: 1,
              schoolName: 'Sunrise Public School',
              name: 'Dept $i',
              hodUserId: null,
              hodName: null,
            ),
        ],
      ),
    );
    addTearDown(container.dispose);
    await container.read(departmentPageNotifierProvider.future);

    await container.read(departmentPageNotifierProvider.notifier).goToPage(2);
    var state = container.read(departmentPageNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(5));

    await container.read(departmentPageNotifierProvider.notifier).setPerPage(50);
    state = container.read(departmentPageNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.items, hasLength(25));
  });
}
