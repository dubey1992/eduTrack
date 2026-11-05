import 'package:edutrack_app/features/academic_years/application/viewed_year.dart';
import 'package:edutrack_app/features/students/application/student_list_notifier.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_student_repository.dart';
import '../../support/viewed_year_overrides.dart';

/// The Students page follows the top bar's year (decided 2026-11-05).
void main() {
  ProviderContainer make(FakeStudentRepository fake) {
    final container = ProviderContainer(
      overrides: [studentRepositoryProvider.overrideWithValue(fake), ...viewedYearIs(null)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('with no year chosen the list is the current one, as before', () async {
    final fake = FakeStudentRepository();
    final container = make(fake);

    await container.read(studentListNotifierProvider.future);

    expect(fake.yearCalls, [null]);
  });

  test('choosing a year reloads the list for it, from page one, with no section carried over', () async {
    final fake = FakeStudentRepository();
    final container = make(fake);
    await container.read(studentListNotifierProvider.future);
    await container.read(studentListNotifierProvider.notifier).setSection(7);

    await container.read(viewedYearIdProvider.notifier).choose(1);
    await container.read(studentListNotifierProvider.future);

    expect(fake.yearCalls.last, 1);
    expect(fake.sectionCalls.last, isNull);
  });

  test('the class list beside it is that year too', () async {
    final fake = FakeStudentRepository();
    final container = make(fake);
    await container.read(viewedYearIdProvider.notifier).choose(1);

    await container.read(studentClassesProvider(null).future);

    expect(fake.classesYearCalls, [1]);
  });

  test('a Super Admin picking a school sees that school, not the top bar year', () async {
    final fake = FakeStudentRepository();
    final container = make(fake);
    await container.read(viewedYearIdProvider.notifier).choose(1);

    await container.read(studentClassesProvider(4).future);

    expect(fake.classesYearCalls, [null]);
  });
}
