import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/school_clock.dart';
import 'auth_notifier.dart';

/// The clock of the signed-in user's school.
///
/// Screens read this instead of calling `DateTime.now()`, so a date picker's
/// default and its bounds are the school's day rather than the day on the
/// laptop the browser happens to be running on. Before anyone signs in it
/// falls back to the device clock, which is all the login screen needs.
final schoolClockProvider = Provider<SchoolClock>((ref) {
  return ref.watch(authNotifierProvider).value?.clock ?? SchoolClock.device();
});
