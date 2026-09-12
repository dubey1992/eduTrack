import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/timezone_option.dart';
import '../data/school_repository.dart';

/// The zones the school form can offer.
///
/// Served by the API and cached for the session: it is reference data that
/// only changes when PHP's timezone database does, so refetching it per
/// dialog would be waste.
/// No automatic retry: while it retried, the picker would sit disabled on
/// "Loading zones..." with no way past it. A failure instead drops the field
/// back to a text box the Super Admin can type into.
final timezoneListProvider = FutureProvider<List<TimezoneOption>>((ref) {
  return ref.watch(schoolRepositoryProvider).listTimezones();
}, retry: (retryCount, error) => null);
