import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/department_repository.dart';
import '../data/models/department.dart';

/// The department pool for the Subject form's department picker. [schoolId]
/// only matters for a SUPER_ADMIN actor picking a specific school - a
/// SCHOOL_ADMIN is already scoped to their own school server-side, so pass
/// `null` for them.
final departmentPickerProvider = FutureProvider.autoDispose.family<List<Department>, int?>((ref, schoolId) {
  return ref.watch(departmentRepositoryProvider).list(schoolId: schoolId);
});
