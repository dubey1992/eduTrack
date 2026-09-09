import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/academic_year_repository.dart';
import '../data/models/academic_year.dart';

/// The academic-year pool for the Class form's year picker. [schoolId] only
/// matters for a SUPER_ADMIN actor picking a specific school - a
/// SCHOOL_ADMIN is already scoped to their own school server-side, so pass
/// `null` for them.
final academicYearPickerProvider = FutureProvider.autoDispose.family<List<AcademicYear>, int?>((ref, schoolId) {
  return ref.watch(academicYearRepositoryProvider).list(schoolId: schoolId);
});
