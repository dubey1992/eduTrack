import 'package:edutrack_app/features/classes/application/class_section_picker_provider.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_class_repository.dart';

/// Class names repeat from one year to the next, so the picker that every
/// "Class" dropdown in the app reads has to know which "Grade 8 A" is the
/// one being lived (docs/promotion.md).
SchoolClass schoolClass({
  required int id,
  required String name,
  required int sectionId,
  bool? isCurrentYear,
  int academicYearId = 1,
}) {
  return SchoolClass(
    id: id,
    schoolId: 1,
    schoolName: 'Green Valley',
    academicYearId: academicYearId,
    academicYearName: '2026-27',
    name: name,
    level: 8,
    isCurrentYear: isCurrentYear,
    sections: [
      ClassSection(
        id: sectionId,
        schoolClassId: id,
        name: 'A',
        roomNumber: null,
        classTeacherId: null,
        classTeacherName: null,
      ),
    ],
  );
}

Future<List<ClassSectionOption>> options(List<SchoolClass> classes) async {
  final container = ProviderContainer(
    overrides: [schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: classes))],
  );
  addTearDown(container.dispose);

  return container.read(classSectionPickerProvider(null).future);
}

void main() {
  test("last year's classes are not offered beside this year's", () async {
    final offered = await options([
      schoolClass(id: 1, name: 'Grade 8', sectionId: 10, isCurrentYear: false, academicYearId: 1),
      schoolClass(id: 2, name: 'Grade 8', sectionId: 20, isCurrentYear: true, academicYearId: 2),
    ]);

    expect(offered.map((option) => option.id), [20]);
    expect(offered.single.label, 'Grade 8 A');
  });

  test('a class that does not say which year it is keeps its place', () async {
    // An older backend, or one that did not load the year: an unknown is not
    // a reason to offer nothing at all.
    final offered = await options([schoolClass(id: 1, name: 'Grade 8', sectionId: 10)]);

    expect(offered.map((option) => option.id), [10]);
  });

  test('a school with nothing current yet is not left with an empty picker', () async {
    final offered = await options([
      schoolClass(id: 1, name: 'Grade 8', sectionId: 10),
      schoolClass(id: 2, name: 'Grade 9', sectionId: 20),
    ]);

    expect(offered.length, 2);
  });
}
