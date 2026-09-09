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

  // This unpaginated provider backs picker-style consumers (e.g. the Staff
  // screen's department filter) - it deliberately has no create/delete/page
  // methods of its own; DepartmentPageNotifier (see
  // department_page_notifier_test.dart) owns those and keeps this provider
  // in sync via invalidation.
  test('build() loads every department, unpaginated', () async {
    final container = makeContainer(FakeDepartmentRepository(departments: [_department]));
    addTearDown(container.dispose);

    final result = await container.read(departmentListNotifierProvider.future);

    expect(result, hasLength(1));
    expect(result.first.name, 'Mathematics');
  });

  test('refresh() re-fetches the full list', () async {
    final fake = FakeDepartmentRepository(departments: [_department]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(departmentListNotifierProvider.future);

    await container.read(departmentListNotifierProvider.notifier).refresh();

    final state = container.read(departmentListNotifierProvider).value;
    expect(state, hasLength(1));
  });
}
