import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';
import '../data/models/working_week.dart';
import 'school_list_notifier.dart';

/// The week one school keeps (docs/holidays.md).
///
/// A school user's own, from the session - they have exactly one school and
/// the server fills it in. A Super Admin belongs to no school and picks one,
/// so passing that school's id resolves to its week instead; otherwise they
/// would be shown Monday-to-Friday columns for a school that keeps Sunday to
/// Thursday, and the server would refuse every cell they tried to fill.
///
/// Falls back to Monday to Friday whenever there is nothing better to say -
/// which is what the server does with a column it cannot read, and what
/// every school had before the setting existed.
final schoolWeekProvider = Provider.family<WorkingWeek, int?>((ref, schoolId) {
  if (schoolId != null) {
    final picked = ref.watch(schoolListNotifierProvider).value?.where((school) => school.id == schoolId).firstOrNull;

    if (picked != null) return picked.workingDays;
  }

  return ref.watch(authNotifierProvider).value?.workingDays ?? const WorkingWeek.mondayToFriday();
});
