import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subjects/data/models/subject.dart';
import '../../subjects/data/subject_repository.dart';

/// The subject pool for the timetable cell editor. [schoolId] only matters
/// for a SUPER_ADMIN actor picking a specific school - a SCHOOL_ADMIN is
/// already scoped to their own school server-side, so pass `null` for them.
final subjectPickerProvider = FutureProvider.autoDispose.family<List<Subject>, int?>((ref, schoolId) {
  return ref.watch(subjectRepositoryProvider).list(schoolId: schoolId);
});
