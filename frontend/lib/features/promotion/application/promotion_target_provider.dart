import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../classes/application/class_section_picker_provider.dart';
import '../../classes/data/school_class_repository.dart';

/// The sections of one academic year, for the promotion wizard's "into
/// class" picker.
///
/// Separate from [classSectionPickerProvider] because that one lists the
/// year a school is in now, and a promotion is into a year it is not in yet.
/// A null year yields nothing rather than everything: until somebody has
/// chosen a year there is no list to show.
final promotionTargetSectionsProvider = FutureProvider.autoDispose.family<List<ClassSectionOption>, int?>((
  ref,
  academicYearId,
) async {
  if (academicYearId == null) return const [];

  final classes = await ref.watch(schoolClassRepositoryProvider).list(academicYearId: academicYearId);

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
