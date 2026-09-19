import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../academic_years/application/academic_year_list_notifier.dart';
import '../../announcements/application/announcement_page_notifier.dart';
import '../../audit/application/audit_log_notifier.dart';
import '../../mail_settings/application/mail_settings_notifier.dart';
import '../../classes/application/school_class_list_notifier.dart';
import '../../communication/application/inbox_notifier.dart';
import '../../communication/application/message_page_notifier.dart';
import '../../dashboard/application/dashboard_notifier.dart';
import '../../departments/application/department_list_notifier.dart';
import '../../early_access/application/early_access_notifier.dart';
import '../../holidays/application/holiday_page_notifier.dart';
import '../../payments/application/payment_list_notifier.dart';
import '../../payments/application/payment_summary_notifier.dart';
import '../../permissions/application/permissions_notifier.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../staff/application/staff_list_notifier.dart';
import '../../staff_leave/application/staff_leave_list_notifier.dart';
import '../../staff_leave/application/staff_leave_summary_notifier.dart';
import '../../students/application/student_list_notifier.dart';
import '../../subjects/application/subject_list_notifier.dart';
import '../../teaching_reports/application/teaching_report_summary_notifier.dart';
import '../../transport/application/driver_page_notifier.dart';
import '../../transport/application/route_page_notifier.dart';
import '../../transport/application/trip_history_notifier.dart';
import '../../transport/application/vehicle_page_notifier.dart';
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

  /// Re-reads the session from /me - what the app gates on (module
  /// switches, permission levels) lives there, so a change made on a settings
  /// screen shows in the sidebar at once rather than at the next sign-in.
  Future<void> refreshSession() async {
    if (!state.hasValue || state.value == null) return;

    final refreshed = await ref.read(authRepositoryProvider).restoreSession();
    if (refreshed != null) state = AsyncData(refreshed);
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

  /// Changes the signed-in user's password and refreshes the session, so a
  /// user who was being held on the change-password screen is let through
  /// the moment it succeeds.
  Future<void> changePassword({required String currentPassword, required String password}) async {
    final user = await ref
        .read(authRepositoryProvider)
        .changePassword(currentPassword: currentPassword, password: password);

    state = AsyncData(user);
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
    // Added in Phase 21, when a sweep found these still holding the previous
    // account's data - on a shared office computer, the next person would
    // briefly see the last person's leave, inbox, dashboard or audit trail.
    // auth_notifier_reset_test.dart now fails when a new one is missed.
    ref.invalidate(announcementPageNotifierProvider);
    ref.invalidate(auditLogNotifierProvider);
    ref.invalidate(mailSettingsNotifierProvider);
    ref.invalidate(dashboardNotifierProvider);
    ref.invalidate(departmentPageNotifierProvider);
    ref.invalidate(driverPageNotifierProvider);
    ref.invalidate(earlyAccessNotifierProvider);
    ref.invalidate(holidayPageNotifierProvider);
    ref.invalidate(inboxNotifierProvider);
    ref.invalidate(messagePageNotifierProvider);
    // The permissions matrix is read on sign-in; a Super Admin who edits
    // it must not hand the previous session's copy to the next account.
    ref.invalidate(permissionsNotifierProvider);
    ref.invalidate(routePageNotifierProvider);
    ref.invalidate(schoolPageNotifierProvider);
    ref.invalidate(staffLeaveListNotifierProvider);
    ref.invalidate(staffLeaveSummaryNotifierProvider);
    ref.invalidate(teachingReportSummaryNotifierProvider);
    ref.invalidate(tripHistoryNotifierProvider);
    ref.invalidate(unreadCountProvider);
    ref.invalidate(vehiclePageNotifierProvider);
  }
}
