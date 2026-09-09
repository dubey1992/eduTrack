import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../academic_years/application/academic_year_list_notifier.dart';
import '../../classes/application/school_class_list_notifier.dart';
import '../../departments/application/department_list_notifier.dart';
import '../../payments/application/payment_list_notifier.dart';
import '../../payments/application/payment_summary_notifier.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../staff/application/staff_list_notifier.dart';
import '../../students/application/student_list_notifier.dart';
import '../../subjects/application/subject_list_notifier.dart';
import '../../users/application/user_list_notifier.dart';
import '../data/auth_repository.dart';
import '../data/models/authenticated_user.dart';

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthenticatedUser?>(AuthNotifier.new);

/// Holds the current session. `null` data means "no one is logged in";
/// loading/error come for free from [AsyncValue] so the UI (via
/// [AsyncValueView]) shows the right state automatically.
class AuthNotifier extends AsyncNotifier<AuthenticatedUser?> {
  @override
  Future<AuthenticatedUser?> build() {
    return ref.read(authRepositoryProvider).restoreSession();
  }

  Future<void> login({required String email, required String password}) async {
    // Deliberately no `state = const AsyncLoading()` here: the router's
    // redirect treats authNotifierProvider.isLoading as "show the splash
    // screen", which is right for the initial session restore in build()
    // but would bounce LoginScreen through /splash and back on every login
    // attempt - tearing it down mid-flight and losing the error listener
    // before a failed login's error ever reaches it. LoginScreen already
    // tracks its own submitting state locally for the button spinner.
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).login(email: email, password: password));
    // Guards against the same browser tab going straight from one signed-in
    // session to another (e.g. testing a School Admin account right after a
    // Super Admin one) without an intervening full reload - without this,
    // every list screen below kept whatever it had already fetched for the
    // PREVIOUS user, since none of these providers are autoDispose or
    // otherwise tied to the session. That looked exactly like a school-data
    // isolation bug even though the API itself was scoping correctly.
    if (state.hasValue) _resetSessionScopedProviders();
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
    _resetSessionScopedProviders();
  }

  /// Every top-level list/summary provider that caches data fetched under
  /// the previous session. New feature list providers need to be added here
  /// too, or they'll leak the outgoing user's data into the next session.
  void _resetSessionScopedProviders() {
    ref.invalidate(schoolListNotifierProvider);
    ref.invalidate(userListNotifierProvider);
    ref.invalidate(studentListNotifierProvider);
    ref.invalidate(staffListNotifierProvider);
    ref.invalidate(departmentListNotifierProvider);
    ref.invalidate(subjectListNotifierProvider);
    ref.invalidate(schoolClassListNotifierProvider);
    ref.invalidate(academicYearListNotifierProvider);
    ref.invalidate(paymentListNotifierProvider);
    ref.invalidate(paymentSummaryNotifierProvider);
  }
}
