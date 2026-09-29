import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/school_class_repository.dart';

/// A single class+section combo for a picker, e.g. "Grade 8 A" - flattened
/// from [SchoolClass.sections] since a student is enrolled into one
/// specific section, not just a class. [classTeacherId] lets a consumer
/// (e.g. the Attendance register picker) narrow this same shared list down
/// to "sections I'm the class teacher of" without a separate endpoint.
class ClassSectionOption {
  const ClassSectionOption({required this.id, required this.label, this.classTeacherId});

  final int id;
  final String label;
  final int? classTeacherId;
}

/// The class-section pool for every "Class" picker in the app. [schoolId]
/// only matters for a SUPER_ADMIN actor picking a specific school - a
/// SCHOOL_ADMIN is already scoped to their own school server-side, so pass
/// `null` for them.
///
/// **This year's sections only.** Class names repeat from one year to the
/// next, so a school in its second year would otherwise offer "Grade 8 A"
/// twice with nothing to tell them apart - and admitting a student into last
/// year's section is not a mistake anybody would notice until a register
/// came up empty (docs/promotion.md). A promotion picks its target year
/// deliberately and uses its own provider.
final classSectionPickerProvider = FutureProvider.autoDispose.family<List<ClassSectionOption>, int?>((
  ref,
  schoolId,
) async {
  final classes = await ref.watch(schoolClassRepositoryProvider).list(schoolId: schoolId);
  // The server says which year is being lived. A class that does not say is
  // kept: an unknown is not a reason to offer nothing.
  final thisYear = classes.where((schoolClass) => schoolClass.isCurrentYear != false);

  return [
    for (final schoolClass in thisYear)
      for (final section in schoolClass.sections)
        ClassSectionOption(
          id: section.id,
          label: '${schoolClass.name} ${section.name}',
          classTeacherId: section.classTeacherId,
        ),
  ];
});
