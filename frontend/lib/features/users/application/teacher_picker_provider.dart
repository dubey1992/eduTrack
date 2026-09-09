import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../data/models/app_user.dart';
import '../data/user_repository.dart';

/// The HOD/Teacher pool for academic-config pickers (department HOD, subject
/// lead teacher, class teacher). [schoolId] only matters for a SUPER_ADMIN
/// actor picking a specific school - a SCHOOL_ADMIN is already scoped to
/// their own school server-side, so pass `null` for them.
final teacherPickerProvider = FutureProvider.autoDispose.family<List<AppUser>, int?>((ref, schoolId) {
  return ref
      .watch(userRepositoryProvider)
      .list(roles: [UserRole.hod, UserRole.teacher], schoolId: schoolId, status: 'active');
});
