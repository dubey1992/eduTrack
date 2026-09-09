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

/// The class-section pool for the Student form's "Class" picker. [schoolId]
/// only matters for a SUPER_ADMIN actor picking a specific school - a
/// SCHOOL_ADMIN is already scoped to their own school server-side, so pass
/// `null` for them.
final classSectionPickerProvider = FutureProvider.autoDispose.family<List<ClassSectionOption>, int?>((
  ref,
  schoolId,
) async {
  final classes = await ref.watch(schoolClassRepositoryProvider).list(schoolId: schoolId);

  return [
    for (final schoolClass in classes)
      for (final section in schoolClass.sections)
        ClassSectionOption(
          id: section.id,
          label: '${schoolClass.name} ${section.name}',
          classTeacherId: section.classTeacherId,
        ),
  ];
});
